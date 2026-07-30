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

    @State var name: String
    @State var caloriesText: String
    @State var proteinText: String
    @State var carbsText: String
    @State var fatText: String
    @State var fiberText: String
    @State var servingDescription: String
    @State private var servings: Double = 1.0
    @State private var mealType: MealType = .suggested()
    @State private var saveAsFavorite = false

    init(result: NutritionAnalysisResult, image: UIImage? = nil, source: LogSource, onFinished: @escaping () -> Void) {
        self.image = image
        self.source = source
        self.onFinished = onFinished
        _name = State(initialValue: result.name)
        _caloriesText = State(initialValue: String(result.calories))
        _proteinText = State(initialValue: String(format: "%.0f", result.proteinG))
        _carbsText = State(initialValue: String(format: "%.0f", result.carbsG))
        _fatText = State(initialValue: String(format: "%.0f", result.fatG))
        _fiberText = State(initialValue: String(format: "%.0f", result.fiberG))
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

                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Serving size", text: $servingDescription)
                    Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                        HStack {
                            Text("Servings")
                            Spacer()
                            Text(servingsLabel)
                                .foregroundStyle(.primary)
                        }
                    }
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                }

                Section("Nutrition (per serving)") {
                    NumericRow(label: "Calories", text: $caloriesText, unit: "kcal")
                    NumericRow(label: "Protein", text: $proteinText, unit: "g")
                    NumericRow(label: "Carbs", text: $carbsText, unit: "g")
                    NumericRow(label: "Fat", text: $fatText, unit: "g")
                    NumericRow(label: "Fiber", text: $fiberText, unit: "g")
                }

                Section {
                    Toggle("Save as favorite meal", isOn: $saveAsFavorite)
                }
            }
            .themedScreenBackground()
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(caloriesText) == nil)
                }
            }
        }
    }

    private var servingsLabel: String {
        servings == servings.rounded() ? "\(Int(servings))" : String(format: "%.1f", servings)
    }

    private func save() {
        let caloriesPerServing = Int(caloriesText) ?? 0
        let proteinPerServing = Double(proteinText) ?? 0
        let carbsPerServing = Double(carbsText) ?? 0
        let fatPerServing = Double(fatText) ?? 0
        let fiberPerServing = Double(fiberText) ?? 0
        let photoData = image?.jpegData(compressionQuality: 0.6)

        let log = FoodLog(
            name: name,
            calories: Int((Double(caloriesPerServing) * servings).rounded()),
            proteinG: proteinPerServing * servings,
            carbsG: carbsPerServing * servings,
            fatG: fatPerServing * servings,
            fiberG: fiberPerServing * servings,
            servingDescription: servingDescription,
            servings: servings,
            mealType: mealType,
            source: source,
            photoData: photoData
        )
        modelContext.insert(log)

        if saveAsFavorite {
            // Favorites store per-serving values so the user can choose servings when re-logging.
            let favorite = SavedMeal(
                name: name,
                calories: caloriesPerServing,
                proteinG: proteinPerServing,
                carbsG: carbsPerServing,
                fatG: fatPerServing,
                fiberG: fiberPerServing,
                servingDescription: servingDescription,
                photoData: photoData
            )
            modelContext.insert(favorite)
        }

        try? modelContext.save()
        onFinished()
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
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
