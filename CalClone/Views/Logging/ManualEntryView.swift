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

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Serving", text: $servingDescription)
                }
                Section("Nutrition") {
                    HStack { Text("Calories"); Spacer(); TextField("0", text: $caloriesText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Protein (g)"); Spacer(); TextField("0", text: $proteinText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Carbs (g)"); Spacer(); TextField("0", text: $carbsText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Fat (g)"); Spacer(); TextField("0", text: $fatText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Fiber (g)"); Spacer(); TextField("0", text: $fiberText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(caloriesText) == nil)
                }
            }
            .fullScreenCover(isPresented: $showConfirm) {
                NutritionConfirmView(
                    result: NutritionAnalysisResult(
                        name: name,
                        calories: Int(caloriesText) ?? 0,
                        proteinG: Double(proteinText) ?? 0,
                        carbsG: Double(carbsText) ?? 0,
                        fatG: Double(fatText) ?? 0,
                        fiberG: Double(fiberText) ?? 0,
                        servingDescription: servingDescription
                    ),
                    source: .manual,
                    onFinished: onFinished
                )
            }
        }
    }
}
