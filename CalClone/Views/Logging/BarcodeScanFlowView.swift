import SwiftUI
import SwiftData

struct BarcodeScanFlowView: View {
    let onFinished: () -> Void

    @State private var isLookingUp = false
    @State private var errorMessage: String?
    @State private var analysisResult: NutritionFacts?
    @State private var manualBarcode = ""
    @State private var lastScanned: String?
    @State private var scannerResetToken = 0
    @State private var selectedSavedFood: SavedMeal?

    var body: some View {
        NavigationStack {
            Group {
                if BarcodeScannerView.isSupported {
                    ZStack(alignment: .bottom) {
                        BarcodeScannerView(onDetect: { code in
                            guard code != lastScanned, !isLookingUp else { return }
                            lastScanned = code
                            lookup(code)
                        }, resetToken: scannerResetToken)
                        .ignoresSafeArea()

                        if isLookingUp {
                            ProgressView("Looking up product…")
                                .padding()
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.bottom, 40)
                        }
                    }
                } else {
                    // Simulator / unsupported hardware fallback.
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "Camera scanning unavailable",
                            systemImage: "barcode.viewfinder",
                            description: Text("Enter a barcode number manually (works on the simulator too).")
                        )
                        TextField("Barcode number", text: $manualBarcode)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                        Button("Look Up") { lookup(manualBarcode) }
                            .buttonStyle(.borderedProminent)
                            .disabled(manualBarcode.isEmpty || isLookingUp)
                        if isLookingUp { ProgressView() }
                    }
                    .padding()
                }
            }
            .overlay(alignment: .top) {
                if let errorMessage {
                    VStack {
                    Text(errorMessage)
                    Button("Scan Again / Retry") {
                        self.errorMessage = nil; lastScanned = nil; scannerResetToken += 1
                        if !BarcodeScannerView.isSupported { lookup(manualBarcode) }
                    }.buttonStyle(.borderedProminent)
                    }
                        .font(.footnote)
                        .padding(8)
                        .background(.red.opacity(0.85))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished() }
                }
            }
            .fullScreenCover(item: $analysisResult) { result in
                NutritionConfirmView(result: result, source: .barcode, savedMeal: selectedSavedFood, onFinished: onFinished)
            }
            .onChange(of: analysisResult) { _, new in
                if new == nil { lastScanned = nil }
            }
        }
    }

    @Query private var savedFoods: [SavedMeal]
    private func lookup(_ code: String) {
        guard !isLookingUp else { return }
        selectedSavedFood = nil
        if let barcode = try? RetailBarcode(code).canonical,
           let food = savedFoods.first(where: { $0.canonicalBarcode == barcode }) {
            selectedSavedFood = food
            analysisResult = NutritionFacts(name: food.name, calories: food.calories, proteinG: food.proteinG,
                carbsG: food.carbsG, fatG: food.fatG, fiberG: food.fiberG, servingDescription: food.servingDescription, barcode: food.canonicalBarcode, sourceRecordID: food.nutritionSourceID, gramsPerServing: food.gramsPerServing, millilitersPerServing: food.millilitersPerServing, caloriesExact: food.caloriesValue)
            return
        }
        isLookingUp = true
        errorMessage = nil
        Task {
            do {
                let result = try await BarcodeLookupService.shared.lookup(barcode: code)
                await MainActor.run {
                    isLookingUp = false
                    analysisResult = result
                }
            } catch {
                await MainActor.run {
                    isLookingUp = false
                    errorMessage = error.localizedDescription
                    // Keep scanning disarmed until the user explicitly retries.
                    // This prevents repeated requests while the same code stays in frame.
                }
            }
        }
    }
}
