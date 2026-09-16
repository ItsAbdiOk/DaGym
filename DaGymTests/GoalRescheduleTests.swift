import Foundation
import GymCore
import SwiftData
import Testing
import UserNotifications

@testable import DaGym

/// S14/F14: only `RemindersSettingsSection`'s three bindings used to call `rescheduleAll` — the
/// weekly-goal stepper in `SettingsView` didn't, so a goal edit left the Saturday "goal at
/// risk" push scheduled with the old, now-stale `remaining` baked into its body. The fix wires
/// `SettingsView`'s goal stepper through the same reschedule call.
@MainActor
@Suite("Weekly goal reschedule")
struct GoalRescheduleTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A Wednesday (Saturday of the same week hasn't happened yet), computed from the device
    /// calendar so the test doesn't depend on which day it actually runs.
    private var wednesday: Date {
        let now = Date()
        let weekday = Calendar.current.component(.weekday, from: now) // 1 = Sunday
        let daysToWednesday = ((4 - weekday) % 7 + 7) % 7 // 4 = Wednesday
        return Calendar.current.date(byAdding: .day, value: daysToWednesday, to: now) ?? now
    }

    private func makeRoutine(store: WorkoutStore) -> UUID {
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    /// Two sessions backfilled onto the Monday and Tuesday before `wednesday`, so they land in the
    /// same week as the scheduler's `now` whichever day the test actually runs on.
    private func logTwoSessionsThisWeek(store: WorkoutStore, routineID: UUID) {
        for daysBefore in 1...2 {
            let date = Calendar.current.date(byAdding: .day, value: -daysBefore, to: wednesday) ?? wednesday
            let session = store.startBackfill(date: date, durationMinutes: 45, routineID: routineID)
            session.exercises[0].sets[0].weightKg = 60
            session.exercises[0].sets[0].reps = 8
            session.exercises[0].sets[0].isDone = true
            _ = store.finish(session: session)
        }
    }

    @Test("lowering the goal to what's already been hit cancels the stale reminder")
    func goalLoweredToMetCancelsReminder() throws {
        let store = try makeStore()
        let routineID = makeRoutine(store: store)
        logTwoSessionsThisWeek(store: store, routineID: routineID)

        let preferences = Preferences(suite: makeSuite(#function))
        preferences.streakRemindersEnabled = true
        preferences.weeklyGoal = 4
        let center = FakeNotificationCenter()
        let scheduler = TrainingNotificationScheduler(center: center)

        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)
        let stale = center.addedRequests.first { $0.identifier == "streak-reminder" }
        #expect(stale?.content.body.contains("2 more") == true)

        // The goal stepper's binding (`SettingsView.weeklyGoalBinding`) does exactly this:
        // update the preference, then reschedule immediately.
        preferences.weeklyGoal = 2
        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        // 2 sessions already meets a goal of 2 — "0 more" needed, so no reminder is pending.
        #expect(center.addedRequests.last { $0.identifier == "streak-reminder" } == nil)
    }

    private final class FakeNotificationCenter: RestNotificationCenter {
        private(set) var addedRequests: [UNNotificationRequest] = []
        private(set) var removedIdentifiers: [[String]] = []

        func add(_ request: UNNotificationRequest) {
            addedRequests.append(request)
        }

        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
            removedIdentifiers.append(identifiers)
            addedRequests.removeAll { identifiers.contains($0.identifier) }
        }
    }
}
