import SwiftUI
import VisionKit
import Vision

/// VisionKit barcode scanner bridge. Falls back to a manual-entry hint if unsupported
/// (e.g. simulator, which has no camera hardware).
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onDetect: (String) -> Void

    /// Symbologies commonly used on food-product packaging.
    private static let foodSymbologies: [VNBarcodeSymbology] = [
        .ean13, .ean8, .upce, .code128, .code39
    ]

    static var isSupported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.foodSymbologies)],
            qualityLevel: .accurate,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDetect: onDetect) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onDetect: (String) -> Void
        init(onDetect: @escaping (String) -> Void) { self.onDetect = onDetect }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(from: addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(from: updatedItems)
        }

        private func deliver(from items: [RecognizedItem]) {
            for item in items {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    onDetect(payload)
                    break
                }
            }
        }
    }
}
