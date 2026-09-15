import Foundation
import Testing

@testable import DaGym

/// Byte-exact vectors for the DER writer and its reader, the zip container and its CRC — the
/// encoding layer under the Wallet pass signature.
@Suite("Wallet DER and zip")
struct WalletDERTests {
    @Test("INTEGER: minimal two's complement with a pad byte when the top bit is set")
    func integers() {
        #expect(DER.integer(0) == [0x02, 0x01, 0x00])
        #expect(DER.integer(1) == [0x02, 0x01, 0x01])
        #expect(DER.integer(127) == [0x02, 0x01, 0x7F])
        #expect(DER.integer(128) == [0x02, 0x02, 0x00, 0x80])
        #expect(DER.integer(256) == [0x02, 0x02, 0x01, 0x00])
        #expect(DER.integer(0x1_0000) == [0x02, 0x03, 0x01, 0x00, 0x00])
    }

    @Test("OID: the two lead arcs share a byte, big arcs use base-128 continuation")
    func oids() {
        let signedData: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
        #expect(DER.oid(CMSOID.signedData) == signedData)
        let sha256: [UInt8] = [0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
        #expect(DER.oid(CMSOID.sha256) == sha256)
        #expect(DER.oid("2.5.4.3") == [0x06, 0x03, 0x55, 0x04, 0x03])
    }

    @Test("SEQUENCE, SET ordering, NULL and long-form lengths")
    func containers() {
        #expect(DER.sequence([DER.integer(1)]) == [0x30, 0x03, 0x02, 0x01, 0x01])
        #expect(DER.null() == [0x05, 0x00])
        // DER SET OF sorts members by their encoding, so INTEGER (0x02) lands before OCTET
        // STRING (0x04) however they were passed.
        let set = DER.set([DER.octetString([0xAA]), DER.integer(1)])
        #expect(set == [0x31, 0x06, 0x02, 0x01, 0x01, 0x04, 0x01, 0xAA])
        #expect(DER.length(127) == [0x7F])
        #expect(DER.length(128) == [0x81, 0x80])
        #expect(DER.length(200) == [0x81, 0xC8])
        #expect(DER.length(300) == [0x82, 0x01, 0x2C])
        #expect(DER.length(70_000) == [0x83, 0x01, 0x11, 0x70])
        #expect(DER.explicit(0, DER.null()) == [0xA0, 0x02, 0x05, 0x00])
    }

    @Test("UTCTime for 2026, GeneralizedTime past 2049")
    func times() throws {
        var parts = DateComponents(year: 2026, month: 9, day: 15, hour: 10, minute: 20, second: 30)
        parts.timeZone = TimeZone(identifier: "UTC")
        let date = try #require(Calendar(identifier: .gregorian).date(from: parts))
        #expect(DER.time(date) == [0x17, 0x0D] + Array("260915102030Z".utf8))
        parts.year = 2051
        let later = try #require(Calendar(identifier: .gregorian).date(from: parts))
        #expect(DER.time(later) == [0x18, 0x0F] + Array("20510915102030Z".utf8))
    }

    @Test("the parser reads back what the writer produced, including long lengths and OIDs")
    func parserRoundTrip() throws {
        let payload = [UInt8](repeating: 0x42, count: 300)
        let encoded = DER.sequence([
            DER.oid(CMSOID.messageDigest), DER.octetString(payload), DER.integer(65_537)
        ])
        let node = try DERParser.parseOne(encoded)
        #expect(node.tag == DER.Tag.sequence)
        #expect(node.raw == encoded)
        let children = node.children
        #expect(children.count == 3)
        #expect(children[0].oidString == CMSOID.messageDigest)
        #expect(children[1].content == payload)
        #expect(children[2].integerValue == 65_537)
        #expect(throws: DERParser.Failure.truncated) { try DERParser.parse([0x30, 0x05, 0x02, 0x01]) }
        #expect(throws: DERParser.Failure.indefiniteLength) { try DERParser.parse([0x30, 0x80, 0x00, 0x00]) }
    }

    @Test("CRC-32 of the check string is the canonical 0xCBF43926")
    func crc32() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test("stored zip: local headers, central directory and EOCD line up and carry the CRCs")
    func zipStructure() throws {
        var zip = ZipWriter()
        zip.modified = Date(timeIntervalSince1970: 1_600_000_000)
        let first = Data("123456789".utf8)
        let second = Data([UInt8](repeating: 0x00, count: 500))
        zip.add("a.txt", first)
        zip.add("dir/b.bin", second)
        let bytes = [UInt8](zip.archive())

        func u16(_ at: Int) -> UInt16 { UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8
                | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }

        // Local header 1 at 0: sig, method 0, crc, sizes, name.
        #expect(u32(0) == ZipWriter.Signature.localFile)
        #expect(u16(8) == 0)
        #expect(u32(14) == 0xCBF4_3926)
        #expect(u32(18) == 9 && u32(22) == 9)
        #expect(u16(26) == 5)
        #expect(Array(bytes[30..<35]) == Array("a.txt".utf8))
        #expect(Array(bytes[35..<44]) == [UInt8](first))
        let secondOffset = 44
        #expect(u32(secondOffset) == ZipWriter.Signature.localFile)
        #expect(u32(secondOffset + 18) == 500)

        // EOCD is the last 22 bytes and points at the central directory.
        let eocd = bytes.count - 22
        #expect(u32(eocd) == ZipWriter.Signature.endOfCentralDirectory)
        #expect(u16(eocd + 8) == 2 && u16(eocd + 10) == 2)
        let directoryOffset = Int(u32(eocd + 16))
        let directorySize = Int(u32(eocd + 12))
        #expect(directoryOffset + directorySize == eocd)
        #expect(u32(directoryOffset) == ZipWriter.Signature.centralDirectory)
        #expect(u32(directoryOffset + 16) == 0xCBF4_3926)
        #expect(u32(directoryOffset + 42) == 0)                     // first entry's local header offset
        let entryLength = 46 + 5
        #expect(u32(directoryOffset + entryLength) == ZipWriter.Signature.centralDirectory)
        #expect(u32(directoryOffset + entryLength + 42) == UInt32(secondOffset))
        #expect(u16(directoryOffset + entryLength + 28) == 9)       // "dir/b.bin"
    }
}
