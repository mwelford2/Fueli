import SwiftUI
import VisionKit
import Vision

/// VisionKit barcode scanner bridge. Falls back to a manual-entry hint if unsupported
/// (e.g. simulator, which has no camera hardware).
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onDetect: (String) -> Void
    /// Bumped by the caller to re-arm detection after a lookup finishes, so the next
    /// steady sighting (of the same or a different barcode) is delivered again.
    var resetToken: Int = 0

    /// Symbologies used on retail food packaging. Deliberately excludes symbologies like
    /// Code 39/128 that show up on shelf tags, coupons, and internal labels — including
    /// them caused the scanner to occasionally lock onto a nearby non-product barcode
    /// (e.g. a shelf tag behind the item) and return the wrong product.
    private static let foodSymbologies: [VNBarcodeSymbology] = [
        .ean13, .ean8, .upce
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

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.reset()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onDetect: onDetect) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onDetect: (String) -> Void
        init(onDetect: @escaping (String) -> Void) { self.onDetect = onDetect }

        /// Consecutive-sighting counts per payload. A single-frame read (e.g. briefly
        /// catching a shelf tag or a second barcode on the package edge) is easy to get
        /// from a moving camera; requiring the same payload to reappear a few times before
        /// acting on it filters those out without meaningfully slowing down a real scan.
        private var sightingCounts: [String: Int] = [:]
        private var delivered = false
        private static let requiredSightings = 3
        var lastResetToken = 0

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(from: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(from: allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in removedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    sightingCounts[payload] = nil
                }
            }
        }

        /// Call when a lookup for the delivered payload finishes (success or failure) so
        /// the scanner is ready to deliver again — e.g. if the user points it at a new item.
        func reset() {
            delivered = false
            sightingCounts.removeAll()
        }

        private func deliver(from items: [RecognizedItem]) {
            guard !delivered else { return }
            var payloadsInFrame: Set<String> = []

            for item in items {
                guard case let .barcode(barcode) = item, let payload = barcode.payloadStringValue else { continue }
                payloadsInFrame.insert(payload)
                let count = (sightingCounts[payload] ?? 0) + 1
                sightingCounts[payload] = count

                if count >= Self.requiredSightings {
                    delivered = true
                    onDetect(payload)
                    return
                }
            }

            // Drop counts for payloads that dropped out of frame this update, so a stray
            // single-frame read doesn't linger and combine with a later, unrelated sighting.
            for key in sightingCounts.keys where !payloadsInFrame.contains(key) {
                sightingCounts[key] = nil
            }
        }
    }
}
