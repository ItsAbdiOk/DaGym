import Foundation
import os

/// Encodes/decodes `BackupDocument` as stable JSON — `VersionedJSONCodec` with the backup's
/// restore-coverage logging on top.
public enum BackupCodec {
    public typealias CodecError = VersionedCodecError

    public static func encode(_ document: BackupDocument) throws -> Data {
        let state = GymCorePerf.signposter.beginInterval("BackupCodec.encode")
        defer { GymCorePerf.signposter.endInterval("BackupCodec.encode", state) }
        return try VersionedJSONCodec<BackupDocument>.encode(document)
    }

    /// Decodes a backup file, then logs which optional sections the file doesn't carry and which
    /// sections it carries that this build can't read (a newer file on an older device), so a
    /// restore that quietly drops photos or coach history leaves a trace. The same lists are on
    /// the document (`absentSections`/`unreadableSections`) for the preview to show.
    public static func decode(_ data: Data) throws -> BackupDocument {
        let state = GymCorePerf.signposter.beginInterval("BackupCodec.decode")
        defer { GymCorePerf.signposter.endInterval("BackupCodec.decode", state) }
        let document = try VersionedJSONCodec<BackupDocument>.decode(data)
        let absent = document.absentSections
        if !absent.isEmpty {
            let names = absent.joined(separator: ", ")
            let version = document.formatVersion
            GymCorePerf.logger.info("Backup (format \(version)) has no \(names, privacy: .public)")
        }
        let unreadable = document.unreadableSections
        if !unreadable.isEmpty {
            let names = unreadable.joined(separator: ", ")
            let version = document.formatVersion
            GymCorePerf.logger.warning("Backup \(version) has unknown sections: \(names, privacy: .public)")
        }
        return document
    }
}
