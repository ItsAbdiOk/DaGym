import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Home snapshot")
struct HomeSnapshotTests {
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Wednesday 2026-01-07, mid-morning.
    private static func wednesday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 7
        components.hour = 10
        return calendar().date(from: components) ?? Date()
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(_ store: WorkoutStore, name: String) -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: "\(name) Exercise", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8)]
        )
        return store.saveRoutine(id: nil, name: name, exercises: [draft])
    }

    @Test("a Wednesday schedule names Wednesday's routine and reads Rest Day on Thursday")
    func followsSchedule() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        let legs = makeRoutine(store, name: "Legs")
        _ = makeRoutine(store, name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.wednesday] = legs.id
        store.saveSchedule(schedule)

        let wednesday = Self.wednesday()
        let thursday = try #require(Self.calendar().date(byAdding: .day, value: 1, to: wednesday))

        let onWednesday = HomeSnapshot.make(store: store, preferences: preferences, now: wednesday)
        #expect(onWednesday.routine?.id == legs.id)
        #expect(onWednesday.headline == "Legs")

        let onThursday = HomeSnapshot.make(store: store, preferences: preferences, now: thursday)
        #expect(onThursday.routine == nil)
        #expect(onThursday.headline == HomeSnapshot.restDayHeadline)
        #expect(onThursday.nextSessionText?.hasPrefix("Next: Legs") == true)
    }

    @Test("this week follows the training calendar's first weekday")
    func thisWeekUsesTrainingCalendar() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        let routineID = makeRoutine(store, name: "Push A").id
        let wednesday = Self.wednesday()
        // Sunday 2026-01-04: the previous week when weeks start Monday, this week when Sunday.
        let sunday = try #require(Self.calendar().date(byAdding: .day, value: -3, to: wednesday))
        let session = store.startBackfill(date: sunday, durationMinutes: 45, routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        preferences.weekStartsMonday = true
        #expect(HomeSnapshot.make(store: store, preferences: preferences, now: wednesday).thisWeekCount == 0)
        preferences.weekStartsMonday = false
        #expect(HomeSnapshot.make(store: store, preferences: preferences, now: wednesday).thisWeekCount == 1)
    }

    @Test("the snapshot's routine and next session agree with the store's own answers")
    func matchesStoreScheduleReads() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        let legs = makeRoutine(store, name: "Legs")
        let push = makeRoutine(store, name: "Push A")
        let wednesday = Self.wednesday()
        let calendar = preferences.trainingCalendar

        // No plan yet: the first routine is offered, and nothing is "next".
        let unplanned = HomeSnapshot.make(store: store, preferences: preferences, now: wednesday)
        #expect(unplanned.routine?.id == store.todaysRoutine(calendar: calendar, now: wednesday)?.id)
        #expect(unplanned.routine?.id == legs.id)
        #expect(unplanned.hasSchedule == false)
        #expect(unplanned.nextSessionText == nil)

        var schedule = WeeklySchedule()
        schedule.days[.wednesday] = legs.id
        schedule.days[.friday] = push.id
        store.saveSchedule(schedule)

        let planned = HomeSnapshot.make(store: store, preferences: preferences, now: wednesday)
        #expect(planned.routine?.id == store.todaysRoutine(calendar: calendar, now: wednesday)?.id)
        #expect(planned.routine?.id == legs.id)
        let storeNext = store.nextSession(calendar: calendar, now: wednesday)
        #expect(planned.nextSessionText == HomeSnapshot.nextSessionText(storeNext))
        #expect(planned.nextSessionText?.hasPrefix("Next: Push A") == true)
    }

    @Test("the snapshot reads the schedule and the routines once each")
    func readsScheduleAndRoutinesOnce() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        let legs = makeRoutine(store, name: "Legs")
        var schedule = WeeklySchedule()
        schedule.days[.wednesday] = legs.id
        store.saveSchedule(schedule)
        let now = Self.wednesday()
        let calendar = preferences.trainingCalendar

        // What the pass delegates to the store unchanged; the snapshot's own reads on top of
        // these must be exactly two — `schedule()` and `routines()` — where going through
        // `todaysRoutine()` and `nextSession()` re-fetched both (4 extra) plus a second
        // `schedule()` for `hasSchedule` and a `routines()` for `hasAnyRoutines` (2 more).
        var before = store.queryCount
        _ = store.workoutDates()
        _ = store.latestBodyMeasurement() // nil here, so no 30-day comparison read follows
        _ = store.recoveryMap(now: now, calendar: calendar)
        _ = store.deloadSuggestion(
            snoozedUntil: nil, weeklyGoal: preferences.weeklyGoal, now: now, calendar: calendar
        )
        let delegated = store.queryCount - before

        before = store.queryCount
        _ = HomeSnapshot.make(store: store, preferences: preferences, now: now)
        #expect(store.queryCount - before == delegated + 2)
    }
}
