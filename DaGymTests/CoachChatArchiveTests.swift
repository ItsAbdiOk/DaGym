import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("Coach chat archive")
struct CoachChatArchiveTests {
    private static let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func temporaryArchive() -> CoachChatArchive {
        let name = "coach-chat-\(UUID().uuidString)"
        return CoachChatArchive(directory: FileManager.default.temporaryDirectory.appending(path: name))
    }

    private func thread(_ question: String, at date: Date) -> CoachChatThread {
        var thread = CoachChatThread(id: UUID(), createdAt: date, updatedAt: date)
        thread.messages = [.user(question, at: date), .assistant("Sure.", at: date)]
        thread.drafts = [.routine(RoutineProposal(
            name: "Pull",
            exercises: [CoachChatExerciseSpec(exerciseName: "Row", sets: [.init(targetReps: 8)])]
        ))]
        thread.usage = CoachChatUsage(promptTokens: 10, completionTokens: 2, costUSD: 0.001)
        return thread
    }

    @Test("save then load round-trips messages, drafts and usage")
    func roundTrip() throws {
        let archive = temporaryArchive()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        let original = thread("Why is my bench stuck?", at: Self.day)
        try archive.save(original)
        #expect(archive.load(id: original.id) == original)
        #expect(FileManager.default.fileExists(atPath: archive.fileURL(for: original.id).path))
    }

    @Test("list is newest first with a title from the first user message")
    func listsNewestFirst() throws {
        let archive = temporaryArchive()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        let older = thread("Older", at: Self.day)
        let long = "Newer question that is long enough to need trimming at sixty characters"
        let newer = thread(long, at: Self.day + 60)
        try archive.save(older)
        try archive.save(newer)
        let list = archive.list()
        #expect(list.map(\.id) == [newer.id, older.id])
        #expect(list.first?.title == "Newer question that is long enough to need trimming at si…")
        #expect(list.last?.title == "Older")
        #expect(list.first?.messageCount == 2)
    }

    @Test("delete removes the file, tolerates a missing one, and unreadable files are skipped")
    func deleteAndSkip() throws {
        let archive = temporaryArchive()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        let thread = thread("Bye", at: Self.day)
        try archive.save(thread)
        try archive.delete(id: thread.id)
        #expect(archive.load(id: thread.id) == nil)
        try archive.delete(id: thread.id)
        try Data("not json".utf8).write(to: archive.fileURL(for: UUID()))
        #expect(archive.list().isEmpty)
    }

    @Test("an empty or missing directory lists nothing")
    func emptyDirectory() {
        let archive = temporaryArchive()
        #expect(archive.list().isEmpty)
        #expect(archive.load(id: UUID()) == nil)
    }

    @Test("the standard archive sits under Application Support/CoachChat")
    func standardLocation() throws {
        let archive = try #require(CoachChatArchive.standard())
        #expect(archive.directory.lastPathComponent == "CoachChat")
        #expect(archive.directory.path.contains("Application Support"))
    }
}
