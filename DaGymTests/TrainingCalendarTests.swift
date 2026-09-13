import Foundation
import GymCore
import SwiftData
import Testing
import UserNotifications

@testable import DaGym

/// X1/D11/S2/S16: "this week" used to mean `Calendar.current` in `Data/` and
/// `weekStartsMonday` in `Progress/`, so a Sunday session could land in different weeks on
/// adjacent screens. `Preferences.trainingCalendar` is the single fix — these tests prove a
/// Sunday session agrees across every consumer once it's threaded through.
@MainActor
@Suite("Training calendar")
struct TrainingCalendarTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The most recent (or today's) Sunday, computed from the actual device calendar so this
    /// test is deterministic without hard-coding a timezone-sensitive literal date.
    private var sunday: Date {
        let now = Date()
        let weekday = Calendar.current.component(.weekday, from: now) // 1 = Sunday
        return Calendar.current.date(byAdding: .day, value: -(weekday - 1), to: now) ?? now
    }

    /// The Wednesday of the same Sunday-starting week — a Monday-first calendar puts `sunday`
    /// in the *previous* week relative to this date, which is exactly the mismatch this batch
    /// fixes.
    private var wednesday: Date {
        Calendar.current.date(byAdding: .day, value: 3, to: sunday) ?? sunday
    }

    private var mondayFirstCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var sundayFirstCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        return calendar
    }

    private func logSundaySession(_ store: WorkoutStore) {
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        let routine = store.saveRoutine(id: nil, name: "Push A", exercises: [draft])
        let session = store.startBackfill(date: sunday, durationMinutes: 40, routineID: routine.id)
        session.exercises[0].sets[0].weightKg = 60
        session.exercises[0].sets[0].reps = 8
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
    }

    @Test("trainingCalendar's firstWeekday follows the preference, not the device locale")
    func trainingCalendarFollowsPreference() {
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weekStartsMonday = true
        #expect(preferences.trainingCalendar.firstWeekday == 2)
        preferences.weekStartsMonday = false
        #expect(preferences.trainingCalendar.firstWeekday == 1)
    }

    @Test("a Sunday session with weekStartsMonday = false counts as this week everywhere")
    func sundaySessionCountsThisWeekEverywhere() throws {
        let store = try makeStore()
        logSundaySession(store)

        // weekStartsMonday == false → `Preferences.trainingCalendar`'s firstWeekday is Sunday.
        let calendar = sundayFirstCalendar

        let streak = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: 1, calendar: calendar, now: wednesday
        )
        #expect(streak.thisWeekCount == 1)

        let state = store.milestoneState(weeklyGoal: 1, calendar: calendar)
        #expect(state.workoutCount == 1)

        let recap = store.weeklyRecap(for: wednesday, weeklyGoal: 1, calendar: calendar)
        #expect(recap.workouts == 1)

        let cells = store.consistencyCells(months: 1, now: wednesday, calendar: calendar)
        let sundayCell = cells.first { calendar.isDate($0.date, inSameDayAs: sunday) }
        #expect((sundayCell?.sets ?? 0) > 0)

        // Same data, same reference date — but a Monday-first calendar (the old
        // `Calendar.current` device-locale behaviour) puts the Sunday session in the
        // *previous* week, proving the mismatch this fix removes was real.
        let mismatched = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: 1, calendar: mondayFirstCalendar,
            now: wednesday
        )
        #expect(mismatched.thisWeekCount == 0)
    }

    @Test("the goal-at-risk reminder agrees: it doesn't fire once the Sunday session met the goal")
    func reminderAgreesWithTrainingCalendar() throws {
        let store = try makeStore()
        logSundaySession(store)

        let preferences = Preferences(suite: makeSuite(#function))
        preferences.weekStartsMonday = false
        preferences.weeklyGoal = 1

        let center = FakeNotificationCenter()
        // No explicit `calendar:` override — production wiring: the scheduler reads
        // `preferences.trainingCalendar` itself on every call.
        let scheduler = TrainingNotificationScheduler(center: center)
        scheduler.rescheduleAll(store: store, preferences: preferences, now: wednesday)

        #expect(center.addedRequests.contains { $0.identifier == "streak-reminder" } == false)
    }

    private final class FakeNotificationCenter: RestNotificationCenter {
        private(set) var addedRequests: [UNNotificationRequest] = []
        func add(_ request: UNNotificationRequest) { addedRequests.append(request) }
        func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    }
}
