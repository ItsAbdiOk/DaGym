import Foundation

/// Encodes/decodes `PlanDocument` as stable JSON — the `.gymplan` file format (plan.md §6.8),
/// via the shared `VersionedJSONCodec`.
public enum PlanCodec {
    public typealias CodecError = VersionedCodecError

    public static func encode(_ document: PlanDocument) throws -> Data {
        try VersionedJSONCodec<PlanDocument>.encode(document)
    }

    /// Decodes a `.gymplan` file. Unknown future fields are ignored (Codable's default
    /// behaviour); a file needing a newer reader than this build fails fast with a typed error
    /// rather than silently dropping data.
    public static func decode(_ data: Data) throws -> PlanDocument {
        try VersionedJSONCodec<PlanDocument>.decode(data)
    }
}
