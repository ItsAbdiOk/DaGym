import Foundation
import os

/// Chat threads on disk: one JSON file per thread under Application Support/CoachChat. Local
/// only — chat never enters the SwiftData container, so it never syncs through CloudKit. Writes
/// are atomic, so a crash mid-save leaves the previous file rather than half of a new one.
struct CoachChatArchive: Sendable {
    let directory: URL

    private static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "coachChat")
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// The app's archive; nil only when Application Support itself can't be found.
    static func standard(fileManager: FileManager = .default) -> CoachChatArchive? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return CoachChatArchive(directory: base.appending(path: "CoachChat", directoryHint: .isDirectory))
    }

    // MARK: - Reads

    /// Newest first. A file that won't decode is skipped and logged, not fatal to the list.
    func list() -> [CoachChatThreadSummary] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CoachChatThreadSummary? in
                guard let thread = decode(at: url) else { return nil }
                return CoachChatThreadSummary(
                    id: thread.id, title: thread.title, updatedAt: thread.updatedAt,
                    messageCount: thread.messages.count
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func load(id: UUID) -> CoachChatThread? {
        decode(at: fileURL(for: id))
    }

    private func decode(at url: URL) -> CoachChatThread? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Self.decoder.decode(CoachChatThread.self, from: data)
        } catch {
            let reason = error.localizedDescription
            Self.logger.error("Skipping unreadable chat thread: \(reason, privacy: .public)")
            return nil
        }
    }

    // MARK: - Writes

    func save(_ thread: CoachChatThread) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(thread)
        try data.write(to: fileURL(for: thread.id), options: .atomic)
    }

    /// Removing a thread that isn't there is not an error.
    func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }
}
