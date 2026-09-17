import Foundation
import GymCore
import Testing

@testable import DaGym

/// What each root tab does on the main thread when it appears, timed against fourteen months
/// of history (the demo lifter: ~200 workouts, ~2 900 sets). The owner felt tab switches lag;
/// this pins the per-switch cost so a regression shows up as a number, not a feeling.
@MainActor
@Suite("Tab switch cost", .serialized)
struct TabSwitchCostTests {
    private static func demoStore() throws -> WorkoutStore {
        let builder = try CoachEvalStoreBuilder()
        var story = DemoLifter(builder: builder)
        try story.build()
        builder.finish()
        return builder.store
    }

    private func timed(_ label: String, _ work: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try work()
        let ms = Double((ContinuousClock.now - start).components.attoseconds) / 1e15
        // The timings are the point of this suite; they go to the test log on purpose.
        // swiftlint:disable:next no_print_statements
        print("PERF tab \(label): \(String(format: "%.1f", ms)) ms")
        return ms
    }

    @Test("every tab's appear-time work stays well under a frame budget on a year of history")
    func appearWork() throws {
        let store = try Self.demoStore()
        let preferences = Preferences(suite: UserDefaults(suiteName: "tab-cost-\(UUID())") ?? .standard)
        // Warm the container once so the first fetch's file open isn't counted against a tab.
        _ = store.routines()

        let shell = timed("RootView.refreshRoutine") {
            let all = store.routines()
            let schedule = store.schedule()
            _ = store.todaysRoutines(from: all, schedule: schedule)
            _ = store.nextSession(from: all, schedule: schedule)
        }
        let today = timed("Today (HomeSnapshot)") {
            _ = HomeSnapshot.make(store: store, preferences: preferences)
        }
        let train = timed("Train (routines + profile)") { _ = store.routines(); _ = store.activeProfile() }
        let you = timed("You (YouSummary)") { _ = YouSummary.make(store: store, preferences: preferences) }
        let history = timed("History (history + stats)") { _ = store.history(); _ = store.lifetimeStats() }
        // The pieces of HomeSnapshot, so a slow one is named.
        _ = timed("  · workoutDates") { _ = store.workoutDates() }
        _ = timed("  · recoveryMap") {
            _ = store.recoveryMap(now: Date(), calendar: preferences.trainingCalendar)
        }
        _ = timed("  · deloadSuggestion") {
            _ = store.deloadSuggestion(
                snoozedUntil: nil, weeklyGoal: preferences.weeklyGoal, now: Date(),
                calendar: preferences.trainingCalendar
            )
        }
        // The second Home refresh of the day (every logged set, every tab return) hits the memo.
        let again = timed("Today again (memoised deload)") {
            _ = HomeSnapshot.make(store: store, preferences: preferences)
        }
        #expect(again < 60, Comment(rawValue: "memoised Home refresh took \(Int(again)) ms"))
        _ = timed("  · weeklyRecap") {
            _ = store.weeklyRecap(weeklyGoal: preferences.weeklyGoal, calendar: preferences.trainingCalendar)
        }

        // Generous: a simulator under a parallel build is slow, and the point is the order of
        // magnitude. A tab that takes a third of a second to appear is the lag being chased.
        let costs = [("shell", shell), ("today", today), ("train", train), ("you", you), ("history", history)]
        for (label, ms) in costs {
            #expect(ms < 350, Comment(rawValue: "\(label) took \(Int(ms)) ms"))
        }
    }
}
