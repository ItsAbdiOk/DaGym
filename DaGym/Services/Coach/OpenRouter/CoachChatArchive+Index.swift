import Foundation
import Synchronization

/// What Home's week-review card needs from a thread without decoding its transcript.
struct CoachChatArchiveEntry: Codable, Equatable, Sendable {
    var id: UUID
    var kind: CoachChatThreadKind
    var weekReviewKey: String?
    var firstReply: String?
    var updatedAt: Date

    init(_ thread: CoachChatThread) {
        id = thread.id
        kind = thread.kind
        weekReviewKey = thread.weekReviewKey
        firstReply = thread.firstReply
        updatedAt = thread.updatedAt
    }
}

/// A sidecar (`.index.json`, hidden so `threads()` never mistakes it for a thread) holding one
/// entry per thread file, keyed by the thread's id string. Threads stay the source of truth: the
/// index is rebuilt from them whenever it is missing, unreadable, or its ids disagree with the
/// directory, so an archive written by an older build — or a crash between the two writes — costs
/// one full decode, not a wrong answer.
struct CoachChatArchiveIndex: Codable, Equatable, Sendable {
    var entries: [String: CoachChatArchiveEntry] = [:]

    static func build(from threads: [CoachChatThread]) -> CoachChatArchiveIndex {
        CoachChatArchiveIndex(entries: Dictionary(
            threads.map { ($0.id.uuidString, CoachChatArchiveEntry($0)) }, uniquingKeysWith: { _, new in new }
        ))
    }
}

extension CoachChatArchive {
    /// One in-memory index per directory, shared by every `CoachChatArchive` value over it
    /// (Home's card and the chat engine each hold their own), updated on every write.
    private static let indexCache = Mutex<[URL: CoachChatArchiveIndex]>([:])

    /// Test hook: how many thread files each directory has decoded in this process, kept per
    /// directory so suites running in parallel don't read each other's counts.
    static let decodeCounts = Mutex<[URL: Int]>([:])

    var decodeCount: Int { Self.decodeCounts.withLock { $0[directory] ?? 0 } }

    var indexURL: URL {
        directory.appending(path: ".index.json", directoryHint: .notDirectory)
    }

    // MARK: - Reads

    /// The week-review thread filed under `weekKey` (`CoachWeekReview.weekKey`), from the index
    /// alone; nil when there is none or its file has since gone.
    func weekReview(weekKey: String) -> CoachChatArchiveEntry? {
        guard let entry = index().entries.values.first(where: {
            $0.kind == .weekReview && $0.weekReviewKey == weekKey
        }), FileManager.default.fileExists(atPath: fileURL(for: entry.id).path)
        else { return nil }
        return entry
    }

    /// The cached index, loaded from disk or rebuilt from the threads when the cache is cold.
    func index() -> CoachChatArchiveIndex {
        if let cached = Self.indexCache.withLock({ $0[directory] }) { return cached }
        let loaded = loadIndex() ?? rebuildIndex()
        Self.indexCache.withLock { $0[directory] = loaded }
        return loaded
    }

    /// Nil when the sidecar is missing, unreadable, or no longer matches the thread files.
    private func loadIndex() -> CoachChatArchiveIndex? {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? Self.decoder.decode(CoachChatArchiveIndex.self, from: data)
        else { return nil }
        let onDisk = Set(threadFileURLs().map { $0.deletingPathExtension().lastPathComponent })
        guard Set(index.entries.keys) == onDisk else { return nil }
        return index
    }

    private func rebuildIndex() -> CoachChatArchiveIndex {
        let index = CoachChatArchiveIndex.build(from: threads())
        try? writeIndex(index)
        return index
    }

    // MARK: - Writes

    /// Cache and persist `index` after a thread file is written or removed, so the index never
    /// lags a save. A failed sidecar write is harmless: the next cold read notices the mismatch.
    func commit(_ index: CoachChatArchiveIndex) {
        Self.indexCache.withLock { $0[directory] = index }
        try? writeIndex(index)
    }

    private func writeIndex(_ index: CoachChatArchiveIndex) throws {
        try Self.encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    /// Drops the in-memory index so the next read goes back to disk; for tests that edit files
    /// behind the archive's back.
    static func resetIndexCache() {
        indexCache.withLock { $0.removeAll() }
    }
}
