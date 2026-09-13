import Foundation

/// Encodes/decodes `PlanDocument` as stable JSON: sorted keys (so two exports of an unchanged
/// routine diff cleanly) and ISO 8601 dates — the `.gymplan` file format (plan.md §6.8).
public enum PlanCodec {
    public enum CodecError: Error, Equatable, Sendable {
        /// The file's `formatVersion` is newer than this build understands.
        case unsupportedFormatVersion(found: Int, supported: Int)
        case decodingFailed(String)
    }

    private struct FormatHeader: Decodable {
        var formatVersion: Int
    }

    public static func encode(_ document: PlanDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Decodes a `.gymplan` file. Unknown future fields are ignored (Codable's default
    /// behaviour); a `formatVersion` newer than this build supports fails fast with a typed
    /// error rather than silently dropping data.
    public static func decode(_ data: Data) throws -> PlanDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: FormatHeader
        do {
            header = try decoder.decode(FormatHeader.self, from: data)
        } catch {
            throw CodecError.decodingFailed(String(describing: error))
        }
        guard header.formatVersion <= PlanDocument.currentFormatVersion else {
            throw CodecError.unsupportedFormatVersion(
                found: header.formatVersion, supported: PlanDocument.currentFormatVersion
            )
        }
        do {
            return try decoder.decode(PlanDocument.self, from: data)
        } catch {
            throw CodecError.decodingFailed(String(describing: error))
        }
    }
}
