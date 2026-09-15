import Foundation

/// One decoded DER element. `raw` is the whole TLV (what a signer copies verbatim — a
/// certificate's issuer `Name`, its serial INTEGER); `content` is the value bytes only.
struct DERNode: Equatable, Sendable {
    let tag: UInt8
    let content: [UInt8]
    let raw: [UInt8]

    var isConstructed: Bool { tag & 0x20 != 0 }

    /// The nested elements of a SEQUENCE / SET / constructed context tag; empty for primitives
    /// or when the content doesn't parse.
    var children: [DERNode] {
        (try? DERParser.parse(content)) ?? []
    }

    /// The dotted form of an OBJECT IDENTIFIER, or nil for any other tag.
    var oidString: String? {
        guard tag == DER.Tag.oid, !content.isEmpty else { return nil }
        var arcs: [UInt64] = []
        var current: UInt64 = 0
        for byte in content {
            current = (current << 7) | UInt64(byte & 0x7F)
            if byte & 0x80 == 0 {
                arcs.append(current)
                current = 0
            }
        }
        guard !arcs.isEmpty else { return nil }
        let lead = arcs.removeFirst()
        let head: [UInt64] = lead < 80 ? [lead / 40, lead % 40] : [2, lead - 80]
        return (head + arcs).map(String.init).joined(separator: ".")
    }

    /// A small non-negative INTEGER's value (nil when it doesn't fit in `UInt64`).
    var integerValue: UInt64? {
        guard tag == DER.Tag.integer, !content.isEmpty else { return nil }
        let significant = content.first == 0 ? Array(content.dropFirst()) : content
        guard significant.count <= 8 else { return nil }
        return significant.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

/// Minimal DER reader — enough to pull issuer + serial out of an X.509 certificate and to let
/// the tests take a `SignedData` apart. Single-byte tags only (no high tag numbers), definite
/// lengths only; both are all DER-encoded certificates and CMS use.
enum DERParser {
    enum Failure: Error, Equatable {
        case truncated
        case indefiniteLength
        case lengthTooLong
    }

    /// Parses every top-level TLV in `bytes`, in order.
    static func parse(_ bytes: [UInt8]) throws -> [DERNode] {
        var nodes: [DERNode] = []
        var offset = 0
        while offset < bytes.count {
            let (node, next) = try readOne(bytes, at: offset)
            nodes.append(node)
            offset = next
        }
        return nodes
    }

    static func parse(_ data: Data) throws -> [DERNode] {
        try parse([UInt8](data))
    }

    /// The single element `bytes` holds (throws when there are zero or several).
    static func parseOne(_ bytes: [UInt8]) throws -> DERNode {
        let nodes = try parse(bytes)
        guard nodes.count == 1, let node = nodes.first else { throw Failure.truncated }
        return node
    }

    private static func readOne(_ bytes: [UInt8], at start: Int) throws -> (DERNode, Int) {
        guard start + 1 < bytes.count else { throw Failure.truncated }
        let tag = bytes[start]
        var offset = start + 1
        var length = Int(bytes[offset])
        offset += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count != 0 else { throw Failure.indefiniteLength }
            guard count <= 4 else { throw Failure.lengthTooLong }
            guard offset + count <= bytes.count else { throw Failure.truncated }
            length = bytes[offset..<offset + count].reduce(0) { ($0 << 8) | Int($1) }
            offset += count
        }
        guard offset + length <= bytes.count else { throw Failure.truncated }
        let content = Array(bytes[offset..<offset + length])
        let raw = Array(bytes[start..<offset + length])
        return (DERNode(tag: tag, content: content, raw: raw), offset + length)
    }
}

/// The two fields of a certificate a CMS `SignerInfo` names the signer by.
struct CertificateIdentity: Equatable, Sendable {
    /// The issuer `Name` as its full DER TLV.
    let issuerDER: [UInt8]
    /// The serialNumber INTEGER as its full DER TLV.
    let serialDER: [UInt8]

    /// Reads TBSCertificate { [0] version OPTIONAL, serialNumber, signature, issuer, ... }.
    init(certificateDER: Data) throws {
        let certificate = try DERParser.parseOne([UInt8](certificateDER))
        guard certificate.tag == DER.Tag.sequence, let tbs = certificate.children.first,
              tbs.tag == DER.Tag.sequence else { throw DERParser.Failure.truncated }
        var fields = tbs.children[...]
        if fields.first?.tag == DER.Tag.context(0) { fields = fields.dropFirst() }
        guard fields.count >= 3, let serial = fields.first, serial.tag == DER.Tag.integer else {
            throw DERParser.Failure.truncated
        }
        let issuer = fields[fields.startIndex + 2]
        guard issuer.tag == DER.Tag.sequence else { throw DERParser.Failure.truncated }
        issuerDER = issuer.raw
        serialDER = serial.raw
    }
}
