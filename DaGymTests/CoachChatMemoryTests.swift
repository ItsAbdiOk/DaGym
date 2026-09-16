import Foundation
import GymCore
import Testing

@testable import DaGym

@MainActor
@Suite("Coach chat memory: remember and recall round-trip through the file beside the archive")
struct CoachChatMemoryTests {
    @Test("remember files a fact the next executor reads back, with topic, expiry and thread")
    func rememberThenRecall() async throws {
        let fixture = try CoachChatToolFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.memory.fileURL.deletingLastPathComponent()) }
        let thread = UUID()
        fixture.executor.sourceThreadID = thread
        let remembered = try await fixture.call(
            .remember, #"{"text":"  Knees hurt on   leg press ","topic":"Injury","expires_in_days":30}"#
        )
        #expect(remembered["fact_count"] as? Int == 1)
        let payload = try #require(remembered["remembered"] as? [String: Any])
        #expect(payload["text"] as? String == "Knees hurt on leg press")
        #expect(payload["topic"] as? String == "injury")
        #expect(payload["created_at"] as? String == "2026-09-15")
        #expect(payload["expires_at"] as? String == "2026-10-15")

        // A second executor over the same file sees the fact: it is on disk, not in memory.
        let reopened = CoachMemoryFile(fileURL: fixture.memory.fileURL, now: { fixture.now })
        let facts = reopened.facts()
        #expect(facts.count == 1)
        #expect(facts.first?.sourceThreadID == thread)
        #expect(facts.first?.topic == .injury)

        _ = try await fixture.call(.remember, #"{"text":"No cable stack at home","topic":"equipment"}"#)
        let all = try await fixture.call(.recall)
        #expect((all["facts"] as? [[String: Any]])?.count == 2)
        let injuries = try await fixture.call(.recall, #"{"topic":"injury"}"#)
        let injuryFacts = try #require(injuries["facts"] as? [[String: Any]])
        #expect(injuryFacts.map { $0["text"] as? String } == ["Knees hurt on leg press"])
        let byWord = try await fixture.call(.recall, #"{"query":"cable"}"#)
        #expect((byWord["facts"] as? [[String: Any]])?.count == 1)
    }

    @Test("a restated fact replaces the old one; bad topic, empty text and a wild expiry are refused")
    func validation() async throws {
        let fixture = try CoachChatToolFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.memory.fileURL.deletingLastPathComponent()) }
        _ = try await fixture.call(.remember, #"{"text":"Hates burpees.","topic":"preference"}"#)
        let again = try await fixture.call(.remember, #"{"text":"hates burpees","topic":"preference"}"#)
        #expect(again["fact_count"] as? Int == 1)
        #expect(fixture.memory.facts().first?.text == "hates burpees")

        await #expect(throws: CoachChatToolError.self) {
            _ = try await fixture.call(.remember, #"{"text":"Trains mornings","topic":"vibes"}"#)
        }
        await #expect(throws: CoachChatToolError.self) {
            _ = try await fixture.call(.remember, #"{"text":"   ","topic":"other"}"#)
        }
        await #expect(throws: CoachChatToolError.self) {
            _ = try await fixture.call(.remember, #"{"text":"No","topic":"injury","expires_in_days":0}"#)
        }
        await #expect(throws: CoachChatToolError.self) {
            _ = try await fixture.call(.recall, #"{"topic":"vibes"}"#)
        }
        #expect(fixture.memory.facts().count == 1)
    }

    @Test("the file drops expired facts on read, forget removes one, forget everything removes the file")
    func fileLifecycle() throws {
        let url = CoachChatToolFixture.temporaryMemoryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let file = CoachMemoryFile(fileURL: url, now: { day })
        let temporary = CoachMemoryFact(
            text: "Back squats off", topic: .injury, createdAt: day - 86_400, expiresAt: day + 3600
        )
        let lasting = CoachMemoryFact(text: "Prefers hack squat", topic: .preference, createdAt: day)
        try file.replaceAll([temporary, lasting])
        #expect(file.facts().map(\.id) == [lasting.id, temporary.id])

        let later = CoachMemoryFile(fileURL: url, now: { day + 7200 })
        #expect(later.facts().map(\.id) == [lasting.id])
        try later.forget(id: lasting.id)
        #expect(later.facts().isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try later.forgetEverything()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try later.forgetEverything()

        try Data("not json".utf8).write(to: url)
        #expect(later.facts().isEmpty)
    }

    @Test("without a memory store the tools answer with a readable error, not a crash")
    func noStore() async throws {
        let fixture = try CoachChatToolFixture.make()
        let bare = StoreCoachChatToolExecutor(
            store: fixture.store, unit: .kg, calendar: fixture.calendar, now: { fixture.now }
        )
        await #expect(throws: CoachChatToolError.self) {
            _ = try await bare.execute(name: "recall", argumentsJSON: "{}")
        }
    }

    @Test("the standard file sits under Application Support/CoachMemory, outside the chat archive")
    func standardLocation() throws {
        let file = try #require(CoachMemoryFile.standard())
        #expect(file.fileURL.lastPathComponent == "facts.json")
        #expect(file.fileURL.deletingLastPathComponent().lastPathComponent == "CoachMemory")
        #expect(file.fileURL.path.contains("Application Support"))
    }
}
