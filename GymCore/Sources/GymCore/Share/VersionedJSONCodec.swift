import Foundation

/// A JSON document that carries its own format version, so a codec can refuse a file this
/// build can't read before handing it to the app. `BackupDocument` and `PlanDocument` both are.
public protocol VersionedDocument: Codable {
    /// The format this build writes.
    static var currentFormatVersion: Int { get }
    /// The oldest reader format that can still restore a file written at `currentFormatVersion`
    /// without losing something essential. Bump it only when a required field is added; an
    /// optional section leaves it alone, so an older build keeps reading newer files and just
    /// reports the sections it doesn't know (`unreadableSections`).
    static var minimumReaderVersion: Int { get }

    var formatVersion: Int { get }
    /// The value the writer stamped; `nil` in files from before it existed, which the codec
    /// reads as "equal to `formatVersion`" — those writers rejected anything newer outright.
    var minimumReaderVersion: Int? { get }
}

/// Why a versioned file couldn't be decoded. One type for every document so the app's error
/// copy and the fuzz tests handle both codecs the same way.
public enum VersionedCodecError: Error, Equatable, Sendable {
    /// The file needs a newer reader than this build: its `minimumReaderVersion` (or, for a
    /// file written before that field existed, its `formatVersion`) is above what we support.
    case unsupportedFormatVersion(found: Int, supported: Int)
    case decodingFailed(String)
}

/// Encodes/decodes a `VersionedDocument` as stable JSON: sorted keys (so two exports of the
/// same data diff cleanly) and ISO 8601 dates. One implementation for backups and `.gymplan`
/// files, so a decoding fix lands in both.
///
/// The file is parsed **once**: the version check reads the decoded document rather than a
/// separate header pass. A photo-bearing backup can be 100+ MB, and parsing it twice doubled
/// peak memory and restore time. Every field added since format 1 is optional, so a newer
/// file still decodes into an older document type and is then checked, not the other way round.
public enum VersionedJSONCodec<Document: VersionedDocument> {
    public static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Decodes a file. Unknown future fields are ignored (Codable's default behaviour); a file
    /// whose `minimumReaderVersion` is newer than this build supports fails fast with a typed
    /// error rather than silently dropping data.
    public static func decode(_ data: Data) throws -> Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: Document
        do {
            document = try decoder.decode(Document.self, from: data)
        } catch {
            // Only on failure — the rare path — a second, two-field parse tells "this file is
            // from a newer format that changed a field's shape" apart from "this file is
            // corrupt", so the user is told to update the app rather than that the file is bad.
            if let header = try? decoder.decode(VersionHeader.self, from: data),
               (header.minimumReaderVersion ?? header.formatVersion) > Document.currentFormatVersion {
                throw VersionedCodecError.unsupportedFormatVersion(
                    found: header.formatVersion, supported: Document.currentFormatVersion
                )
            }
            throw VersionedCodecError.decodingFailed(String(describing: error))
        }
        let required = document.minimumReaderVersion ?? document.formatVersion
        guard required <= Document.currentFormatVersion else {
            throw VersionedCodecError.unsupportedFormatVersion(
                found: document.formatVersion, supported: Document.currentFormatVersion
            )
        }
        return document
    }
}

/// The two fields the failure path reads to classify an undecodable file.
private struct VersionHeader: Decodable {
    var formatVersion: Int
    var minimumReaderVersion: Int?
}
