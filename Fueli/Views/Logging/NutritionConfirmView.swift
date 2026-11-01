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
                Section("Food") {
                    TextField("Name", text: $name)
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
                        .disabled(!isValid)
                    Button(savedMeal == nil ? "Save to My Foods" : "Update Saved Food") { save(toLibrary: true) }
                        .disabled(!isValid)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            }
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
            let photoData = image?.jpegData(compressionQuality: 0.6)
            if toLibrary {
                if let savedMeal {
                    savedMeal.name = name
                    savedMeal.calories = Int(standard.calories.rounded())
                    savedMeal.caloriesExact = standard.calories
                    savedMeal.proteinG = standard.protein
                    savedMeal.carbsG = standard.carbohydrates
                    savedMeal.fatG = standard.fat
                    savedMeal.fiberG = standard.fiber
                    savedMeal.servingDescription = servingDescription
                    savedMeal.gramsPerServing = referenceGrams
                    savedMeal.millilitersPerServing = referenceMilliliters
                } else {
                    let item = SavedMeal(name: name, calories: Int(standard.calories.rounded()),
                        proteinG: standard.protein, carbsG: standard.carbohydrates, fatG: standard.fat,
                        fiberG: standard.fiber, servingDescription: servingDescription, photoData: photoData)
                    item.caloriesExact = standard.calories
                    item.ingredientData = try result.ingredients.map { try JSONEncoder().encode($0) }
                    item.canonicalBarcode = result.barcode
                    item.nutritionSourceID = result.sourceRecordID
                    item.gramsPerServing = referenceGrams
                    item.millilitersPerServing = referenceMilliliters
                    if let barcode = item.canonicalBarcode,
                       let existing = try modelContext.fetch(FetchDescriptor<SavedMeal>()).first(where: { $0.canonicalBarcode.map { BarcodeLookupService.sameGTIN($0, barcode) } == true }) {
                        errorMessage = "This barcode is already saved as \(existing.name). Edit it in My Foods to update its values."
                        return
                    }
                    modelContext.insert(item)
                }
            } else {
                let total = try standard.scaled(by: servings)
                savedMeal?.timesLogged += 1
                savedMeal?.lastLoggedAt = Date()
                let entry = FoodLog(name: name, calories: Int(total.calories.rounded()),
                    proteinG: total.protein, carbsG: total.carbohydrates, fatG: total.fat, fiberG: total.fiber,
                    servingDescription: servingDescription, servings: servings, mealType: mealType,
                    source: source, photoData: photoData)
                entry.caloriesExact = total.calories
                entry.savedFoodID = savedMeal?.id
                entry.recipeIngredientsData = try result.ingredients.map { try JSONEncoder().encode($0) } ?? savedMeal?.ingredientData
                modelContext.insert(entry)
            }
            try modelContext.save()
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
    var body: some View {
        HStack {
            Button { servings = max(0.01, servings - 0.25) } label: { Image(systemName: "minus.circle") }
                .accessibilityLabel("Decrease servings")
            TextField("Servings", value: $servings, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.center)
                .accessibilityLabel("Number of standard servings")
            Button { servings = min(10_000, servings + 0.25) } label: { Image(systemName: "plus.circle") }
                .accessibilityLabel("Increase servings")
            Text("servings")
        }.buttonStyle(.borderless)
    }
}

private struct NumericRow: View {
    let label: String
    @Binding var text: String
    let unit: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Required", text: $text).keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing).frame(width: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
