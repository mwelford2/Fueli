import SwiftUI

struct ManualEntryView: View {
    let onFinished: () -> Void

    @State private var showConfirm = false
    @State private var name = ""
    @State private var servingDescription = "1 serving"
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var fiberText = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Double(caloriesText).map { $0.isFinite && $0 >= 0 && $0 <= 1000000 } == true &&
        [proteinText, carbsText, fatText, fiberText].allSatisfy { text in
            Double(text).map { $0.isFinite && $0 >= 0 && $0 <= 1000000 } ?? false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Serving", text: $servingDescription)
                }
                Section("Nutrition — enter 0 for a known zero") {
                    HStack { Text("Calories"); Spacer(); TextField("0", text: $caloriesText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Protein (g)"); Spacer(); TextField("0", text: $proteinText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Carbs (g)"); Spacer(); TextField("0", text: $carbsText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Fat (g)"); Spacer(); TextField("0", text: $fatText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Fiber (g)"); Spacer(); TextField("0", text: $fiberText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
            }
            .themedScreenBackground()
            .navigationTitle("Manual Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { showConfirm = true }
                        .disabled(!isValid)
                }
            }
            .fullScreenCover(isPresented: $showConfirm) {
                NutritionConfirmView(
                    result: NutritionFacts(
                        name: name,
                        calories: Int((Double(caloriesText) ?? 0).rounded()),
                        proteinG: Double(proteinText) ?? 0,
                        carbsG: Double(carbsText) ?? 0,
                        fatG: Double(fatText) ?? 0,
                        fiberG: Double(fiberText) ?? 0,
                        servingDescription: servingDescription, caloriesExact: Double(caloriesText)
                    ),
                    source: .manual,
                    onFinished: onFinished
                )
            }
        }
    }
}
