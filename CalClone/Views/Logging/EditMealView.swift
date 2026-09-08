import SwiftUI
import SwiftData

/// Edits an already-logged meal in place. Reached by tapping a logged row on the
/// dashboard or in History.
struct EditMealView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var log: FoodLog

    @State private var name: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var fiberText: String
    @State private var servingDescription: String
    @State private var servings: Double
    @State private var mealType: MealType
    @State private var loggedAt: Date
    @State private var notes: String
    @State private var showDeleteConfirm = false

    init(log: FoodLog) {
        self.log = log
        _name = State(initialValue: log.name)
        _caloriesText = State(initialValue: String(log.calories))
        _proteinText = State(initialValue: String(format: "%.0f", log.proteinG))
        _carbsText = State(initialValue: String(format: "%.0f", log.carbsG))
        _fatText = State(initialValue: String(format: "%.0f", log.fatG))
        _fiberText = State(initialValue: String(format: "%.0f", log.fiberG))
        _servingDescription = State(initialValue: log.servingDescription)
        _servings = State(initialValue: log.servings)
        _mealType = State(initialValue: log.mealType)
        _loggedAt = State(initialValue: log.loggedAt)
        _notes = State(initialValue: log.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let data = log.photoData, let uiImage = UIImage(data: data) {
                    Section {
                        Image(uiImage: uiImage)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 200)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Meal") {
                    TextField("Name", text: $name)
                    TextField("Serving size", text: $servingDescription)
                    Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                        HStack {
                            Text("Servings")
                            Spacer()
                            Text(servings == servings.rounded() ? "\(Int(servings))" : String(format: "%.1f", servings))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    DatePicker("Logged at", selection: $loggedAt)
                }

                Section("Nutrition (total)") {
                    EditNumericRow(label: "Calories", text: $caloriesText, unit: "kcal")
                    EditNumericRow(label: "Protein", text: $proteinText, unit: "g")
                    EditNumericRow(label: "Carbs", text: $carbsText, unit: "g")
                    EditNumericRow(label: "Fat", text: $fatText, unit: "g")
                    EditNumericRow(label: "Fiber", text: $fiberText, unit: "g")
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Button("Delete meal", role: .destructive) { showDeleteConfirm = true }
                        .frame(maxWidth: .infinity)
                }
            }
            .themedScreenBackground()
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(caloriesText) == nil)
                }
            }
            .confirmationDialog("Delete this meal?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(log)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }

    private func save() {
        log.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        log.calories = Int(caloriesText) ?? log.calories
        log.proteinG = Double(proteinText) ?? log.proteinG
        log.carbsG = Double(carbsText) ?? log.carbsG
        log.fatG = Double(fatText) ?? log.fatG
        log.fiberG = Double(fiberText) ?? log.fiberG
        log.servingDescription = servingDescription
        log.servings = servings
        log.mealType = mealType
        log.loggedAt = loggedAt
        log.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        try? modelContext.save()
        dismiss()
    }
}

private struct EditNumericRow: View {
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
