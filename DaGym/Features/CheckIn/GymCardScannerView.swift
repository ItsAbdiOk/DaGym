import SwiftUI
import UIKit
import Vision
import VisionKit

/// Live camera barcode scanner for adding a gym card (features.md adopt 6): VisionKit's
/// `DataScannerViewController` reads the first barcode it sees and hands back its payload and
/// symbology. Check `isSupported` first — a simulator or a device without a camera can't run it,
/// and `GymCardSheet` offers the photo/manual routes instead.
struct GymCardScannerView: UIViewControllerRepresentable {
    var onScan: (String, GymCardSymbology) -> Void

    @MainActor
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String, GymCardSymbology) -> Void
        private var delivered = false

        init(onScan: @escaping (String, GymCardSymbology) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !delivered else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                      !payload.isEmpty else { continue }
                delivered = true
                dataScanner.stopScanning()
                onScan(payload, GymCardSymbology(vision: barcode.observation.symbology))
                return
            }
        }
    }
}

/// The photo route: runs `VNDetectBarcodesRequest` over a picked image and returns the first
/// barcode's payload and symbology, or nil when the photo holds no readable code.
enum PhotoBarcodeDetector {
    static func detect(in data: Data) async -> (value: String, symbology: GymCardSymbology)? {
        await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(data: data)
            guard (try? handler.perform([request])) != nil else { return nil }
            let found = (request.results ?? []).first { ($0.payloadStringValue ?? "").isEmpty == false }
            guard let found, let payload = found.payloadStringValue else { return nil }
            return (value: payload, symbology: GymCardSymbology(vision: found.symbology))
        }.value
    }
}
