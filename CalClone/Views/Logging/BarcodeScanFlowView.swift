import SwiftUI

struct BarcodeScanFlowView: View {
    let onFinished: () -> Void

    @State private var isLookingUp = false
    @State private var errorMessage: String?
    @State private var analysisResult: NutritionAnalysisResult?
    @State private var manualBarcode = ""
    @State private var lastScanned: String?

    var body: some View {
        NavigationStack {
            Group {
                if BarcodeScannerView.isSupported {
                    ZStack(alignment: .bottom) {
                        BarcodeScannerView { code in
                            guard code != lastScanned, !isLookingUp else { return }
                            lastScanned = code
                            lookup(code)
                        }
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
                    Text(errorMessage)
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
                NutritionConfirmView(result: result, source: .barcode, onFinished: onFinished)
            }
            .onChange(of: analysisResult) { _, new in
                if new == nil { lastScanned = nil }
            }
        }
    }

    private func lookup(_ code: String) {
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
                    lastScanned = nil
                }
            }
        }
    }
}
