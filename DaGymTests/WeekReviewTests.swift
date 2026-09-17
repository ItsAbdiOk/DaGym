import Foundation
import GymCore
import Testing

@testable import DaGym

@MainActor
@Suite("Week review: the Sunday check-in is due over a seeded store and runs as a chat turn")
struct WeekReviewTests {
    private typealias Fake = FakeOpenRouterTransport

    private func preferences() -> Preferences {
        let name = "week-review-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name) ?? .standard
        suite.removePersistentDomain(forName: name)
        return Preferences(suite: suite)
    }

    private func temporaryArchive() -> CoachChatArchive {
        let name = "week-review-archive-\(UUID().uuidString)"
        return CoachChatArchive(directory: FileManager.default.temporaryDirectory.appending(path: name))
    }

    /// Logs a finished session on `date` through the same path the fixture uses.
    private func log(_ fixture: CoachChatToolFixture, on date: Date) {
        let session = fixture.store.startBackfill(
            date: date, durationMinutes: 40, routineID: fixture.routine.id
        )
        for exercise in session.exercises.indices {
            for index in session.exercises[exercise].sets.indices {
                session.exercises[exercise].sets[index].weightKg = 60
                session.exercises[exercise].sets[index].reps = 8
                session.exercises[exercise].sets[index].isDone = true
            }
        }
        _ = fixture.store.finish(session: session)
    }

    @Test("due on Sunday with two sessions in the week; hidden when dismissed, unconfigured or thin")
    func dueOverSeededStore() throws {
        let fixture = try CoachChatToolFixture.make()
        let archive = temporaryArchive()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        let preferences = preferences()
        let calendar = fixture.calendar
        // The fixture logs Mon 7 and Mon 14 September; add Wed 16 so the week ending Sun 20 has two.
        log(fixture, on: fixture.now.addingTimeInterval(86_400))
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9)))

        var state = WeekReviewState.make(
            store: fixture.store, preferences: preferences, archive: archive, isConfigured: true, now: sunday
        )
        #expect(state.status.weekKey == "2026-09-20")
        #expect(state.status.workoutCount == 2)
        #expect(state.status.isDue)
        #expect(state.isVisible)
        #expect(state.threadID == nil)
        #expect(state.headline == nil)

        // Still the same week on the Wednesday after, so still due.
        let wednesday = sunday.addingTimeInterval(3 * 86_400)
        state = WeekReviewState.make(
            store: fixture.store, preferences: preferences, archive: archive, isConfigured: true,
            now: wednesday
        )
        #expect(state.status.isDue)

        state = WeekReviewState.make(
            store: fixture.store, preferences: preferences, archive: archive, isConfigured: false, now: sunday
        )
        #expect(!state.isVisible)

        preferences.coachWeekReviewDismissedKey = "2026-09-20"
        state = WeekReviewState.make(
            store: fixture.store, preferences: preferences, archive: archive, isConfigured: true, now: sunday
        )
        #expect(!state.isVisible)
        preferences.coachWeekReviewDismissedKey = nil

        // The week before had one session only.
        let previousSunday = sunday.addingTimeInterval(-7 * 86_400)
        state = WeekReviewState.make(
            store: fixture.store, preferences: preferences, archive: archive, isConfigured: true,
            now: previousSunday
        )
        #expect(state.status.workoutCount == 1)
        #expect(!state.isVisible)
    }

    @Test("a filed review thread turns the card into its headline, and it opens on that thread")
    func threadHeadline() throws {
        let fixture = try CoachChatToolFixture.make()
        let archive = temporaryArchive()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        let preferences = preferences()
        log(fixture, on: fixture.now.addingTimeInterval(86_400))
        let sunday = try #require(fixture.calendar.date(from: DateComponents(year: 2026, month: 9, day: 20)))
        var thread = CoachChatThread(
            id: UUID(), createdAt: sunday, updatedAt: sunday, kind: .weekReview, weekReviewKey: "2026-09-20"
        )
        thread.messages = [.user("Weekly check-in", at: sunday), .note("Couldn't reach", at: sunday)]
        try archive.save(thread)
        var state = WeekReviewState.make(
            store: fixture.store, preferences: preferences, archive: archive, isConfigured: true, now: sunday
        )
        #expect(state.isVisible)
        #expect(!state.status.isDue)
        #expect(state.threadID == thread.id)
        #expect(state.headline == nil)

        thread.messages.append(.assistant("Bench moved from 77.5 to 80 kg.\nRows held.", at: sunday))
        try archive.save(thread)
        state = WeekReviewState.make(
            store: fixture.store, preferences: preferences, archive: archive, isConfigured: true, now: sunday
        )
        #expect(state.headline == "Bench moved from 77.5 to 80 kg.")
        // Home refreshes on every store change; the card must never decode a transcript.
        #expect(archive.decodeCount == 0)
        #expect(archive.list().first?.title == "Week review · 2026-09-20")
    }

    @Test("startWeekReview files the thread as a review, sends the canned turn once, and persists")
    func engineStartsReview() async throws {
        let archive = temporaryArchive()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20)))
        let transport = Fake([Fake.Reply(lines: Fake.sse([
            Fake.text("Bench moved up."), Fake.finish("stop"), Fake.usage(prompt: 40, completion: 4)
        ]))])
        let engine = CoachChatEngine(
            client: OpenRouterClient(apiKey: { "or-test" }, transport: transport),
            executor: FakeCoachChatToolExecutor(),
            configuration: CoachChatConfiguration(reviewerModelID: nil, consentGiven: true),
            systemPrompt: "You are a coach.", tools: [], archive: archive, clock: { sunday }
        )
        await engine.startWeekReview(weekEnding: sunday, calendar: calendar)
        #expect(engine.kind == .weekReview)
        #expect(engine.weekReviewKey == "2026-09-20")
        #expect(engine.messages.map(\.role) == [.user, .assistant])
        let turn = CoachWeekReviewPrompt.userTurn(weekEnding: sunday, calendar: calendar)
        #expect(engine.messages.first?.text == turn)
        let saved = try #require(archive.weekReviewThread(weekKey: "2026-09-20"))
        #expect(saved.id == engine.threadID)
        #expect(saved.firstReply == "Bench moved up.")
        #expect(saved.title == "Week review · 2026-09-20")

        // Already has messages: a second start does nothing.
        await engine.startWeekReview(weekEnding: sunday, calendar: calendar)
        #expect(engine.messages.count == 2)
        #expect(transport.chatRequest(at: 1) == nil)
    }
}
