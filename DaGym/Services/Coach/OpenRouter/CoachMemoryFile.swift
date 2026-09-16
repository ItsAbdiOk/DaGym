import Foundation
import GymCore
import os

/// The coach's memory on disk: one JSON file under Application Support/CoachMemory, beside the
/// chat archive and like it local only — never the SwiftData container, so it never syncs
/// through CloudKit. Writes are atomic. Every read runs `CoachMemoryValidation.merged` at
/// `now`, so an expired fact disappears on its own and a file edited by hand is still deduped
/// and capped.
@MainActor
final class CoachMemoryFile: CoachMemoryStore {
    let fileURL: URL
    let now: () -> Date

    private static let logger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "coachChat")
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(fileURL: URL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    /// The app's memory file; nil only when Application Support itself can't be found.
    static func standard(fileManager: FileManager = .default) -> CoachMemoryFile? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = base.appending(path: "CoachMemory", directoryHint: .isDirectory)
        return CoachMemoryFile(fileURL: directory.appending(path: "facts.json", directoryHint: .notDirectory))
    }

    // MARK: - CoachMemoryStore

    func facts() -> [CoachMemoryFact] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let stored = try Self.decoder.decode([CoachMemoryFact].self, from: data)
            return CoachMemoryValidation.merged(stored, now: now())
        } catch {
            let reason = error.localizedDescription
            Self.logger.error("Unreadable coach memory, treating as empty: \(reason, privacy: .public)")
            return []
        }
    }

    func replaceAll(_ facts: [CoachMemoryFact]) throws {
        let cleaned = CoachMemoryValidation.merged(facts, now: now())
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encoder.encode(cleaned).write(to: fileURL, options: .atomic)
    }

    // MARK: - Conveniences

    /// Files one fact; a restatement of an existing one replaces it. Returns the list as stored.
    @discardableResult
    func remember(_ fact: CoachMemoryFact) throws -> [CoachMemoryFact] {
        let merged = CoachMemoryValidation.merged(facts(), adding: [fact], now: now())
        try replaceAll(merged)
        return merged
    }

    func forget(id: UUID) throws {
        try replaceAll(facts().filter { $0.id != id })
    }

    /// Removes the file itself, so nothing lingers on disk.
    func forgetEverything() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
