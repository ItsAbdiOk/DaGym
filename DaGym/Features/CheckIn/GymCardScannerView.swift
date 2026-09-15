import OSLog
import SwiftUI
import UIKit
import Vision
import VisionKit

private let scannerLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "checkin")

/// Live camera barcode scanner for adding a gym card (features.md adopt 6): VisionKit's
/// `DataScannerViewController` reads the first barcode it sees and hands back its payload and
/// symbology. Check `isSupported` first — a simulator or a device without a camera can't run it,
/// and `GymCardSheet` offers the photo/manual routes instead. `startScanning` can still throw
/// (camera access denied, another app holding it); `onFailure` carries a user-facing reason so
/// the sheet can say so rather than leave a black cover up.
struct GymCardScannerView: UIViewControllerRepresentable {
    var onScan: (String, GymCardSymbology) -> Void
    var onFailure: (String) -> Void

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
        do {
            try scanner.startScanning()
        } catch {
            scannerLogger.error(
                "Gym card scanner failed to start: \(error.localizedDescription, privacy: .public)"
            )
            context.coordinator.reportFailure(Self.failureMessage(for: error))
        }
    }

    /// Plain-language reason for a `startScanning` failure. `ScanningUnavailable` is the only
    /// documented error type; anything else falls through to a generic line.
    static func failureMessage(for error: Error) -> String {
        switch error as? DataScannerViewController.ScanningUnavailable {
        case .cameraRestricted:
            "Camera access is off for DaGym — allow it in Settings."
        case .unsupported:
            "This device can't scan barcodes with the camera."
        default:
            "The camera couldn't start."
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onFailure: onFailure) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String, GymCardSymbology) -> Void
        private let onFailure: (String) -> Void
        private var delivered = false

        init(onScan: @escaping (String, GymCardSymbology) -> Void, onFailure: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onFailure = onFailure
        }

        /// Delivered at most once: `updateUIViewController` re-runs on every parent render and
        /// would otherwise re-report the same failure.
        func reportFailure(_ reason: String) {
            guard !delivered else { return }
            delivered = true
            onFailure(reason)
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
