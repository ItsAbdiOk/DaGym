import Foundation

/// A minimal DER (ASN.1 Distinguished Encoding Rules) writer — just the primitives a CMS
/// `SignedData` needs (`WalletPassSigner`). Every function returns the complete TLV
/// (tag, length, value) bytes so callers compose them by nesting.
enum DER {
    enum Tag {
        static let integer: UInt8 = 0x02
        static let octetString: UInt8 = 0x04
        static let null: UInt8 = 0x05
        static let oid: UInt8 = 0x06
        static let utf8String: UInt8 = 0x0C
        static let utcTime: UInt8 = 0x17
        static let generalizedTime: UInt8 = 0x18
        static let sequence: UInt8 = 0x30
        static let set: UInt8 = 0x31
        /// `[n]` context-specific, constructed (EXPLICIT wrappers and IMPLICIT SETs).
        static func context(_ number: UInt8) -> UInt8 { 0xA0 | (number & 0x1F) }
    }

    /// The length octets: short form under 128, else `0x80 | count` followed by big-endian bytes.
    static func length(_ count: Int) -> [UInt8] {
        precondition(count >= 0, "DER length must be non-negative")
        if count < 0x80 { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    /// Non-negative INTEGER: minimal big-endian two's complement, so a leading 0x00 pads any
    /// value whose top bit is set.
    static func integer(_ value: UInt64) -> [UInt8] {
        var bytes: [UInt8] = []
        var remaining = value
        repeat {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        } while remaining > 0
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(Tag.integer, bytes)
    }

    /// Dotted OID ("1.2.840.113549.1.7.2"). The first two arcs share one byte (40·a + b);
    /// every arc is base-128 with continuation bits.
    static func oid(_ dotted: String) -> [UInt8] {
        let arcs = dotted.split(separator: ".").compactMap { UInt64($0) }
        precondition(arcs.count >= 2, "OID needs at least two arcs")
        var content: [UInt8] = base128(arcs[0] * 40 + arcs[1])
        for arc in arcs.dropFirst(2) { content += base128(arc) }
        return tlv(Tag.oid, content)
    }

    private static func base128(_ value: UInt64) -> [UInt8] {
        var bytes: [UInt8] = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        return bytes
    }

    static func sequence(_ elements: [[UInt8]]) -> [UInt8] {
        tlv(Tag.sequence, elements.flatMap { $0 })
    }

    /// SET OF — DER requires the members sorted by their encoded bytes.
    static func set(_ elements: [[UInt8]]) -> [UInt8] {
        tlv(Tag.set, sorted(elements).flatMap { $0 })
    }

    /// `[n] IMPLICIT SET OF` — same sorting as `set`, different tag.
    static func implicitSet(_ number: UInt8, _ elements: [[UInt8]]) -> [UInt8] {
        tlv(Tag.context(number), sorted(elements).flatMap { $0 })
    }

    /// `[n] EXPLICIT` wrapper around one already-encoded element.
    static func explicit(_ number: UInt8, _ element: [UInt8]) -> [UInt8] {
        tlv(Tag.context(number), element)
    }

    static func octetString(_ bytes: [UInt8]) -> [UInt8] {
        tlv(Tag.octetString, bytes)
    }

    static func octetString(_ data: Data) -> [UInt8] {
        octetString([UInt8](data))
    }

    static func null() -> [UInt8] {
        [Tag.null, 0x00]
    }

    /// UTCTime `YYMMDDhhmmssZ` for 1950–2049, GeneralizedTime `YYYYMMDDhhmmssZ` outside that
    /// window — the split X.509/CMS mandate.
    static func time(_ date: Date) -> [UInt8] {
        let parts = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = parts.year ?? 1970
        let fields = [parts.month, parts.day, parts.hour, parts.minute, parts.second]
            .map { String(format: "%02d", $0 ?? 0) }
            .joined()
        if (1950..<2050).contains(year) {
            return tlv(Tag.utcTime, Array("\(String(format: "%02d", year % 100))\(fields)Z".utf8))
        }
        return tlv(Tag.generalizedTime, Array("\(String(format: "%04d", year))\(fields)Z".utf8))
    }

    /// AlgorithmIdentifier ::= SEQUENCE { algorithm OID, parameters NULL }.
    static func algorithm(_ oid: String, nullParameters: Bool = true) -> [UInt8] {
        sequence(nullParameters ? [Self.oid(oid), null()] : [Self.oid(oid)])
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func sorted(_ elements: [[UInt8]]) -> [[UInt8]] {
        elements.sorted { $0.lexicographicallyPrecedes($1) }
    }
}
