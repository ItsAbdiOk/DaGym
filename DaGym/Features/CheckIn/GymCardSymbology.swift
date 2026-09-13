import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// What kind of code a gym card carries, and how to draw it back. Core Image can only generate
/// QR, Aztec, PDF417 and Code 128, so every 1-D retail symbology (EAN, UPC, Code 39, ITF…) is
/// stored under its own name but rendered as Code 128 — the same digits, a format every gym
/// scanner reads (features.md adopt 6).
enum GymCardSymbology: String, CaseIterable, Sendable {
    case qr, aztec, pdf417, code128
    case ean13, ean8, upce, code39, code93, itf14, dataMatrix

    /// Maps what Vision detected onto a stored case; unknown symbologies fall back to Code 128
    /// for 1-D-looking payloads.
    init(vision symbology: VNBarcodeSymbology) {
        self = Self.visionMap[symbology] ?? .code128
    }

    private static let visionMap: [VNBarcodeSymbology: GymCardSymbology] = [
        .qr: .qr, .aztec: .aztec, .pdf417: .pdf417, .code128: .code128,
        .ean13: .ean13, .ean8: .ean8, .upce: .upce,
        .code39: .code39, .code39Checksum: .code39, .code39FullASCII: .code39,
        .code39FullASCIIChecksum: .code39,
        .code93: .code93, .code93i: .code93,
        .itf14: .itf14, .i2of5: .itf14, .i2of5Checksum: .itf14,
        .dataMatrix: .dataMatrix
    ]

    /// True for the square 2-D codes, which the card draws as a square instead of a strip.
    var isTwoDimensional: Bool {
        switch self {
        case .qr, .aztec, .dataMatrix, .pdf417: true
        default: false
        }
    }

    /// Which Core Image generator draws this symbology back.
    var generatorName: String {
        switch self {
        case .qr, .dataMatrix: "CIQRCodeGenerator"
        case .aztec: "CIAztecCodeGenerator"
        case .pdf417: "CIPDF417BarcodeGenerator"
        default: "CICode128BarcodeGenerator"
        }
    }

    var title: String {
        switch self {
        case .qr: "QR"
        case .aztec: "Aztec"
        case .pdf417: "PDF417"
        case .code128: "Code 128"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .upce: "UPC-E"
        case .code39: "Code 39"
        case .code93: "Code 93"
        case .itf14: "ITF"
        case .dataMatrix: "Data Matrix"
        }
    }
}

/// Regenerates a card's image from its payload — nothing but the value and symbology is ever
/// stored. Output is crisp at any size: the generator's tiny bitmap is scaled with nearest-
/// neighbour sampling so modules stay square and scanners keep reading it.
enum BarcodeRenderer {
    /// A black-on-white code, or nil when Core Image can't encode the payload (an empty string,
    /// bytes Code 128 can't carry).
    static func image(value: String, symbology: GymCardSymbology, scale: CGFloat = 8) -> UIImage? {
        guard !value.isEmpty, let data = value.data(using: .isoLatin1) ?? value.data(using: .utf8),
              let filter = CIFilter(name: symbology.generatorName) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        if symbology.generatorName == "CIQRCodeGenerator" {
            filter.setValue("M", forKey: "inputCorrectionLevel")
        }
        if symbology.generatorName == "CICode128BarcodeGenerator" {
            filter.setValue(0, forKey: "inputQuietSpace")
        }
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
