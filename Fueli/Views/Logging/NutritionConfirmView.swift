import SwiftUI
import SwiftData

/// Editable confirmation screen shown after an AI/barcode/manual estimate is produced,
/// before it's committed to the log — lets the user correct the AI's guess.
struct NutritionConfirmView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let onFinished: () -> Void
    let image: UIImage?
    let source: LogSource
    
    var result: NutritionFacts

    @State var name: String
    @State var caloriesText: String
    @State var proteinText: String
    @State var carbsText: String
    @State var fatText: String
    @State var fiberText: String
    @State var servingDescription: String
    @State private var servings: Double = 1.0
    @State private var quantityUnit = "servings"
    @State private var weightQuantity = 100.0
    @State private var gramsText = ""
    @State private var millilitersText = ""
    @State private var mealType: MealType = .suggested()
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var committer = NutritionCommitter()
    private let savedMeal: SavedMeal?

    init(result: NutritionFacts, image: UIImage? = nil, source: LogSource, savedMeal: SavedMeal? = nil, onFinished: @escaping () -> Void) {
        self.savedMeal = savedMeal
        self.result = result
        self.image = image ?? savedMeal?.photoData.flatMap(UIImage.init(data:))
        self.source = source
        self.onFinished = onFinished
        _gramsText = State(initialValue: (result.gramsPerServing ?? savedMeal?.gramsPerServing).map { String($0) } ?? "")
        _millilitersText = State(initialValue: (result.millilitersPerServing ?? savedMeal?.millilitersPerServing).map { String($0) } ?? "")
        _name = State(initialValue: result.name)
        _caloriesText = State(initialValue: String(result.caloriesValue))
        _proteinText = State(initialValue: String(result.proteinG))
        _carbsText = State(initialValue: String(result.carbsG))
        _fatText = State(initialValue: String(result.fatG))
        _fiberText = State(initialValue: String(result.fiberG))
        _servingDescription = State(initialValue: result.servingDescription)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 200)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if source == .photo || source == .textDescription {
                    Section("Portion estimates") {
                        Text("Nutrition is calculated from matched food records and your reviewed quantities. Photo and description portions are estimates; confirm weights, preparation, oils and sauces before logging.").font(.caption)
                    }
                }
                if result.sourceRecordID?.hasPrefix("OFF:") == true || result.ingredients?.contains(where: { $0.sourceRecordID?.hasPrefix("OFF:") == true }) == true {
                    Section("Open Food Facts") {
                        Text("Community-supplied package nutrition, calculated using your reviewed quantities. Confirm the product, preparation and label before logging. Database: ODbL; individual contents: Database Contents License.").font(.caption)
                        Link("Open Food Facts data and licenses", destination: URL(string: "https://world.openfoodfacts.org/data")!)
                    }
                }
                Section("Food") {
                    TextField("Name", text: $name).accessibilityIdentifier("confirm.name")
                    TextField("Serving size", text: $servingDescription)
                    if quantityUnit == "servings" { ServingSelector(servings: $servings) }
                    DisclosureGroup("Standard serving weight / volume (optional)") {
                        TextField("Grams per standard serving", text: $gramsText).keyboardType(.decimalPad)
                        TextField("Milliliters per standard serving", text: $millilitersText).keyboardType(.decimalPad)
                        Text("Enter only an item-specific weight or volume you know. Volume is never converted to mass without both definitions.").font(.caption)
                    }
                    if referenceGrams != nil || referenceMilliliters != nil {
                        Picker("Measure by", selection: $quantityUnit) {
                            Text("Servings").tag("servings")
                            if referenceGrams != nil { Text("Grams").tag("g"); Text("Ounces").tag("oz") }
                            if referenceMilliliters != nil { Text("Milliliters").tag("mL"); Text("US fluid ounces").tag("fl oz") }
                        }.onChange(of: quantityUnit) { _, unit in
                            if let reference = reference(for: unit) { weightQuantity = servings * reference / conversionFactor(for: unit) }
                        }
                        if quantityUnit != "servings" {
                            TextField("Amount", value: $weightQuantity, format: .number).keyboardType(.decimalPad)
                                .onChange(of: weightQuantity) { _, _ in updateQuantity() }
                        }
                    }
                    if let total = try? standard?.scaled(by: servings) {
                        Text("Selected total: \(Int(total.calories.rounded())) kcal")
                        Text("Protein \(total.protein.formatted()) g · Carbs \(total.carbohydrates.formatted()) g · Fat \(total.fat.formatted()) g")
                            .font(.caption)
                    }
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                }

                if let ingredients = result.ingredients ?? savedMeal?.ingredientData.flatMap({ try? JSONDecoder().decode([LibraryIngredient].self, from: $0) }) {
                    Section("Calculated ingredients") {
                        ForEach(ingredients) { ingredient in
                            VStack(alignment: .leading) {
                                Text(ingredient.name)
                                if let grams = ingredient.gramsPerServing { Text("\((grams * ingredient.servings).formatted()) g").font(.caption) }
                                Text("\(ingredient.servings.formatted()) standard portions · \(ingredient.sourceRecordID ?? "Saved food snapshot")").font(.caption)
                                if let preparation = ingredient.preparation, !preparation.isEmpty { Text(preparation).font(.caption) }
                                if let basis = ingredient.measureBasis { Text("Nutrition basis: " + basis.rawValue.replacingOccurrences(of: "_", with: " ")).font(.caption) }
                                if ingredient.quantityIsEstimated == true { Text("Reviewed portion estimate — not a scale measurement").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        Text("Recipe nutrition is calculated from ingredients. Edit saved recipe ingredients in My Foods.").font(.caption)
                    }
                }
                Section(isRecipe ? "Nutrition calculated per standard recipe portion" : "Nutrition per standard serving (editable)") {
                    NumericRow(label: "Calories", text: $caloriesText, unit: "kcal")
                    NumericRow(label: "Protein", text: $proteinText, unit: "g")
                    NumericRow(label: "Carbs", text: $carbsText, unit: "g")
                    NumericRow(label: "Fat", text: $fatText, unit: "g")
                    NumericRow(label: "Fiber", text: $fiberText, unit: "g")
                }.disabled(isRecipe)

                Section {
                    Button("Log Food") { save(toLibrary: false) }
                        .disabled(!isValid || committer.loggedID != nil)
                    Button(savedMeal == nil ? "Save to My Foods" : "Update Saved Food") { save(toLibrary: true) }
                        .disabled(!isValid)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .themedScreenBackground()
            .onChange(of: gramsText) { _, _ in updateQuantity() }
            .onChange(of: millilitersText) { _, _ in updateQuantity() }
            .alert("Saved to My Foods", isPresented: Binding(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil } })) {
                Button("Done") { savedMessage = nil; onFinished() }
            } message: { Text(savedMessage ?? "") }
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished() }
                }

            }
        }
    }
    
    private var servingsLabel: String {
        servings == servings.rounded() ? "\(Int(servings))" : String(format: "%.1f", servings)
    }

    private var isRecipe: Bool { result.ingredients != nil || savedMeal?.ingredientData != nil }
    private var referenceGrams: Double? { validReference(gramsText) }
    private var referenceMilliliters: Double? { validReference(millilitersText) }
    private func validReference(_ text: String) -> Double? {
        guard let amount = Double(text), amount.isFinite, amount > 0, amount <= 1000000 else { return nil }
        return amount
    }
    private func reference(for unit: String) -> Double? {
        if unit == "g" || unit == "oz" { return referenceGrams }
        if unit == "mL" || unit == "fl oz" { return referenceMilliliters }
        return nil
    }
    private func conversionFactor(for unit: String) -> Double {
        unit == "oz" ? 28.349523125 : unit == "fl oz" ? 29.5735295625 : 1
    }
    private func updateQuantity() {
        guard quantityUnit != "servings" else { return }
        guard let reference = reference(for: quantityUnit) else { quantityUnit = "servings"; return }
        servings = weightQuantity * conversionFactor(for: quantityUnit) / reference
    }

    private var standard: ServingNutrition? {
        guard let c = Double(caloriesText), let p = Double(proteinText),
              let carbs = Double(carbsText), let f = Double(fatText), let fiber = Double(fiberText) else { return nil }
        return try? ServingNutrition(calories: c, protein: p, carbohydrates: carbs, fat: f, fiber: fiber)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && standard != nil &&
        (gramsText.isEmpty || referenceGrams != nil) && (millilitersText.isEmpty || referenceMilliliters != nil) &&
        servings.isFinite && servings > 0 && servings <= 10_000
    }

    private func save(toLibrary: Bool) {
        guard let standard, isValid else { return }
        do {
            _ = try committer.commit(context: modelContext, toLibrary: toLibrary, result: result, standard: standard,
                name: name, serving: servingDescription, grams: referenceGrams, milliliters: referenceMilliliters,
                servings: servings, meal: mealType, source: source, savedMeal: savedMeal,
                photo: image?.jpegData(compressionQuality: 0.6))
            if toLibrary {
                savedMessage = "Saved one standard serving of \(name): \(Int(standard.calories.rounded())) kcal. No food was added to your daily log."
            } else { onFinished() }
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

struct ServingSelector: View {
    @Binding var servings: Double
    @FocusState private var isEditing: Bool
    @State private var amountText = ""
    var body: some View {
        HStack {
            Button { servings = max(0.01, (servings.isFinite ? servings : 1) - 0.25); syncText() } label: { Image(systemName: "minus.circle") }
                .accessibilityLabel("Decrease servings")
            TextField("Servings", text: $amountText).accessibilityIdentifier("serving.amount")
                .keyboardType(.decimalPad).multilineTextAlignment(.center)
                .focused($isEditing)
                .contentShape(Rectangle())
                .onTapGesture { isEditing = true }
                .accessibilityLabel("Number of standard servings")
            Button { servings = min(10_000, (servings.isFinite ? servings : 1) + 0.25); syncText() } label: { Image(systemName: "plus.circle") }
                .accessibilityLabel("Increase servings")
            Text("servings")
        }.buttonStyle(.borderless)
            .onAppear { syncText() }
            .onChange(of: amountText) { _, text in
                let normalized = text.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
                let next = Double(normalized) ?? .nan
                if next != servings { servings = next }
            }
            .onChange(of: servings) { _, _ in if !isEditing { syncText() } }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isEditing { Spacer(); Button("Done Editing") { isEditing = false } }
                }
            }
    }
    private func syncText() {
        let next = servings.isFinite ? String(servings).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".") : ""
        if amountText != next { amountText = next }
    }
}

private struct NumericRow: View {
    let label: String
    @Binding var text: String
    let unit: String
    @FocusState private var isEditing: Bool
    @State private var selection: TextSelection?
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Required", text: $text, selection: $selection).accessibilityIdentifier("confirm." + label).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(width: 100)
                .focused($isEditing)
                .onChange(of: isEditing) { _, focused in
                    if focused { selection = TextSelection(range: text.startIndex..<text.endIndex) }
                }
            Text(unit).foregroundStyle(.secondary)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isEditing { Spacer(); Button("Done Editing") { isEditing = false } }
            }
        }
    }
}
