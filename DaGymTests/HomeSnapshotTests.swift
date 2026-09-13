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
}
