import Foundation

/// Encodes/decodes `BackupDocument` as stable JSON: sorted keys (so two
/// exports of identical data diff cleanly) and ISO 8601 dates.
public enum BackupCodec {
    public enum CodecError: Error, Equatable, Sendable {
        /// The file's `formatVersion` is newer than this build understands.
        case unsupportedFormatVersion(found: Int, supported: Int)
        case decodingFailed(String)
    }

    private struct FormatHeader: Decodable {
        var formatVersion: Int
    }

    public static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Decodes a backup file. Unknown future fields are ignored (Codable's
    /// default behaviour); a `formatVersion` newer than this build supports
    /// fails fast with a typed error rather than silently dropping data.
    public static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: FormatHeader
        do {
            header = try decoder.decode(FormatHeader.self, from: data)
        } catch {
            throw CodecError.decodingFailed(String(describing: error))
        }
        guard header.formatVersion <= BackupDocument.currentFormatVersion else {
            throw CodecError.unsupportedFormatVersion(
                found: header.formatVersion, supported: BackupDocument.currentFormatVersion
            )
        }
        do {
            return try decoder.decode(BackupDocument.self, from: data)
        } catch {
            throw CodecError.decodingFailed(String(describing: error))
        }
    }
}
