import Foundation

/// The barcode formats Wallet draws. Everything else a gym card can carry (EAN, UPC, Code 39…)
/// is re-encoded as Code 128 with the number as `altText` — same digits, but a gym's scanner
/// may not read the substitute, which is why the sheet says so.
enum WalletBarcodeFormat: String, Codable, Sendable {
    case qr = "PKBarcodeFormatQR"
    case pdf417 = "PKBarcodeFormatPDF417"
    case aztec = "PKBarcodeFormatAztec"
    case code128 = "PKBarcodeFormatCode128"
}

extension GymCardSymbology {
    /// The Wallet format for this symbology, mirroring how the app itself redraws the card
    /// (`generatorName`): Data Matrix goes out as QR, every 1-D retail code as Code 128.
    var walletFormat: WalletBarcodeFormat {
        switch self {
        case .qr, .dataMatrix: .qr
        case .aztec: .aztec
        case .pdf417: .pdf417
        default: .code128
        }
    }

    /// True when Wallet shows the very symbology the card was scanned in.
    var isWalletNative: Bool {
        switch self {
        case .qr, .aztec, .pdf417, .code128: true
        default: false
        }
    }
}

/// `pass.json` for a generic-style gym card. Keys match Apple's pass schema verbatim.
struct WalletPassJSON: Codable, Equatable, Sendable {
    struct Barcode: Codable, Equatable, Sendable {
        var format: WalletBarcodeFormat
        var message: String
        var messageEncoding: String
        var altText: String?
    }

    struct Field: Codable, Equatable, Sendable {
        var key: String
        var label: String
        var value: String
    }

    struct Generic: Codable, Equatable, Sendable {
        var primaryFields: [Field]
        var secondaryFields: [Field]
    }

    static let passTypeIdentifier = "pass.dev.abdirahmanmohamed.dagym"
    static let teamIdentifier = "5AF2LBU5A3"
    static let organizationName = "DaGym"

    var formatVersion = 1
    var passTypeIdentifier = Self.passTypeIdentifier
    var teamIdentifier = Self.teamIdentifier
    var serialNumber: String
    var organizationName = Self.organizationName
    var description: String
    var logoText = Self.organizationName
    var backgroundColor: String
    var foregroundColor: String
    var labelColor: String
    var barcode: Barcode
    var barcodes: [Barcode]
    var generic: Generic

    /// Throws `valueNotEncodable` when the number can't be carried in ISO-8859-1, the encoding
    /// every scanner-facing barcode uses.
    init(card: GymCardInfo, accent: DGAccent) throws {
        guard !card.value.isEmpty, card.value.data(using: .isoLatin1) != nil else {
            throw WalletPassError.valueNotEncodable
        }
        let barcode = Barcode(
            format: card.symbology.walletFormat, message: card.value, messageEncoding: "iso-8859-1",
            altText: card.symbology.isWalletNative ? nil : card.value
        )
        serialNumber = card.id.uuidString
        description = "\(card.name) membership"
        backgroundColor = WalletPassStyle.rgb(accent.baseHex(dark: true))
        foregroundColor = WalletPassStyle.rgb(WalletPassStyle.inkHex)
        labelColor = WalletPassStyle.rgb(WalletPassStyle.labelHex)
        self.barcode = barcode
        barcodes = [barcode]
        generic = Generic(
            primaryFields: [Field(key: "gym", label: "GYM", value: card.name)],
            secondaryFields: [Field(key: "member", label: "MEMBER NUMBER", value: card.value)]
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }
}

/// Pass colours: the brand accent's dark-mode stop (the brighter, designed-for-black one) as
/// the ground, dark ink on it — every accent is a light, saturated hue that dark text reads on.
enum WalletPassStyle {
    /// `DGColor.ink1`'s light-scheme value: near-black ink.
    static let inkHex: UInt32 = 0x12_1213
    /// Ink at roughly two-thirds strength for labels, pre-blended (Wallet takes no alpha).
    static let labelHex: UInt32 = 0x4A_3A38

    /// `rgb(r, g, b)` as Wallet's schema wants it.
    static func rgb(_ hex: UInt32) -> String {
        "rgb(\((hex >> 16) & 0xFF), \((hex >> 8) & 0xFF), \(hex & 0xFF))"
    }
}
