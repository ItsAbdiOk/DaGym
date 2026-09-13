import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore schedule")
struct WorkoutStoreScheduleTests {
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Monday 2026-01-05.
    private static func monday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        return calendar().date(from: components) ?? Date()
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

    @Test("an unsaved schedule is empty and round-trips through save")
    func saveAndLoadRoundTrip() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))

        #expect(store.schedule() == WeeklySchedule())

        let pushA = makeRoutine(store, name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        store.saveSchedule(schedule)

        #expect(store.schedule().days[.monday] == pushA.id)
    }

    @Test("todaysRoutine falls back to the first routine only when nothing has ever been scheduled")
    func todaysRoutineFallback() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))

        let pushA = makeRoutine(store, name: "Push A")
        _ = makeRoutine(store, name: "Pull B")

        // No schedule saved yet: falls back to the first routine, like before this feature.
        #expect(store.todaysRoutine(calendar: Self.calendar(), now: Self.monday())?.id == pushA.id)
    }

    @Test("todaysRoutine follows the saved weekly plan, including a rest day")
    func todaysRoutineFollowsSchedule() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))

        let pushA = makeRoutine(store, name: "Push A")
        let monday = Self.monday()
        let tuesday = Self.calendar().date(byAdding: .day, value: 1, to: monday) ?? monday

        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        store.saveSchedule(schedule)

        #expect(store.todaysRoutine(calendar: Self.calendar(), now: monday)?.id == pushA.id)
        // Tuesday has no entry, so once a schedule exists it means "rest", not "fall back".
        #expect(store.todaysRoutine(calendar: Self.calendar(), now: tuesday) == nil)
    }

    @Test("nextSession finds the next planned routine and skips rest days")
    func nextSessionSkipsRest() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))

        let pushA = makeRoutine(store, name: "Push A")
        let legs = makeRoutine(store, name: "Legs")
        let monday = Self.monday()
        let wednesday = Self.calendar().date(byAdding: .day, value: 2, to: monday) ?? monday

        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        schedule.days[.wednesday] = legs.id
        store.saveSchedule(schedule)

        let next = store.nextSession(calendar: Self.calendar(), now: monday)
        #expect(next?.routine.id == legs.id)
        if let nextDate = next?.date {
            #expect(Self.calendar().isDate(nextDate, inSameDayAs: wednesday))
        } else {
            Issue.record("expected a next session")
        }
    }

    @Test("event ID map round-trips through save/load")
    func eventIDsRoundTrip() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))

        #expect(store.scheduleEventIDs().isEmpty)
        store.saveScheduleEventIDs(["2026-01-05": "event-1"])
        #expect(store.scheduleEventIDs() == ["2026-01-05": "event-1"])
    }
}
