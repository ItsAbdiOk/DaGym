import Foundation

/// A stored (method 0, no compression) zip archive built in memory — the container a `.pkpass`
/// is. Local file headers, a central directory and the end-of-central-directory record, in
/// that order; every entry carries its CRC-32 so Wallet's unzip validates it.
struct ZipWriter {
    struct Entry {
        var name: String
        var data: Data
    }

    /// Signatures the reader (and the tests) look for.
    enum Signature {
        static let localFile: UInt32 = 0x0403_4B50
        static let centralDirectory: UInt32 = 0x0201_4B50
        static let endOfCentralDirectory: UInt32 = 0x0605_4B50
    }

    var entries: [Entry] = []
    /// Stamped on every entry; fixed by the caller so the archive is reproducible.
    var modified = Date()

    mutating func add(_ name: String, _ data: Data) {
        entries.append(Entry(name: name, data: data))
    }

    func archive() -> Data {
        var body = Data()
        var directory = Data()
        let (dosTime, dosDate) = Self.dosTimestamp(modified)
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(clamping: entry.data.count)
            let offset = UInt32(clamping: body.count)

            body.append(Self.le32(Signature.localFile))
            body.append(Self.le16(20))              // version needed: 2.0
            body.append(Self.le16(0x0800))          // flags: UTF-8 names
            body.append(Self.le16(0))               // method: stored
            body.append(Self.le16(dosTime))
            body.append(Self.le16(dosDate))
            body.append(Self.le32(crc))
            body.append(Self.le32(size))            // compressed
            body.append(Self.le32(size))            // uncompressed
            body.append(Self.le16(UInt16(clamping: name.count)))
            body.append(Self.le16(0))               // extra length
            body.append(name)
            body.append(entry.data)

            directory.append(Self.le32(Signature.centralDirectory))
            directory.append(Self.le16(20))         // version made by
            directory.append(Self.le16(20))         // version needed
            directory.append(Self.le16(0x0800))
            directory.append(Self.le16(0))
            directory.append(Self.le16(dosTime))
            directory.append(Self.le16(dosDate))
            directory.append(Self.le32(crc))
            directory.append(Self.le32(size))
            directory.append(Self.le32(size))
            directory.append(Self.le16(UInt16(clamping: name.count)))
            directory.append(Self.le16(0))          // extra length
            directory.append(Self.le16(0))          // comment length
            directory.append(Self.le16(0))          // disk number start
            directory.append(Self.le16(0))          // internal attributes
            directory.append(Self.le32(0))          // external attributes
            directory.append(Self.le32(offset))
            directory.append(name)
        }

        var archive = body
        archive.append(directory)
        archive.append(Self.le32(Signature.endOfCentralDirectory))
        archive.append(Self.le16(0))                // this disk
        archive.append(Self.le16(0))                // disk with central directory
        archive.append(Self.le16(UInt16(clamping: entries.count)))
        archive.append(Self.le16(UInt16(clamping: entries.count)))
        archive.append(Self.le32(UInt32(clamping: directory.count)))
        archive.append(Self.le32(UInt32(clamping: body.count)))
        archive.append(Self.le16(0))                // comment length
        return archive
    }

    /// MS-DOS packed time/date (2-second resolution, years from 1980), in local time.
    static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let parts = Calendar.current.dateComponents(units, from: date)
        let year = max((parts.year ?? 1980) - 1980, 0)
        let time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        let day = UInt16(min(year, 127) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        return (time, day)
    }

    static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)
        ])
    }
}

/// The zip / PNG CRC-32 (reflected, polynomial 0xEDB88320).
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
