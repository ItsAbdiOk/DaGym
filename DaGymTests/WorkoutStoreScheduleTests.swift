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

    /// `nextSession` used to take the planned day's *first* routine id and give up when that
    /// routine had been deleted, so one stale id blanked Home's "Next:" card entirely instead
    /// of showing the session after it.
    @Test("a planned day whose routines are all gone is skipped, not fatal")
    func nextSessionSkipsDeletedRoutines() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))
        let doomed = makeRoutine(store, name: "Doomed")
        let legs = makeRoutine(store, name: "Legs")
        var schedule = WeeklySchedule()
        schedule.days[.tuesday] = doomed.id
        schedule.days[.wednesday] = legs.id
        store.saveSchedule(schedule)
        // Deleted straight out of the store, leaving the schedule id behind — the state a
        // pre-fix install (or a CloudKit merge) can still be in.
        store.deleteRoutineModelOnly(id: doomed.id)

        let next = store.nextSession(calendar: Self.calendar(), now: Self.monday())
        #expect(next?.routine.id == legs.id)
    }

    /// A day that still has a second, surviving routine reports that one.
    @Test("a day whose first routine is gone reports its second")
    func nextSessionFallsBackToSecondRoutine() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))
        let doomed = makeRoutine(store, name: "Doomed")
        let arms = makeRoutine(store, name: "Arms")
        var schedule = WeeklySchedule()
        schedule.addRoutine(doomed.id, to: .tuesday)
        schedule.addRoutine(arms.id, to: .tuesday)
        store.saveSchedule(schedule)
        store.deleteRoutineModelOnly(id: doomed.id)

        let next = store.nextSession(calendar: Self.calendar(), now: Self.monday())
        #expect(next?.routine.id == arms.id)
    }

    /// `deleteRoutine` has to take the id out of every plan that points at it, or the schedule
    /// keeps showing a blank planned day and the routine's calendar events have nothing left
    /// that can ever remove them.
    @Test("deleting a routine scrubs it from the schedule, overrides and programs")
    func deletingARoutineScrubsEveryPlan() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        let store = WorkoutStore(context: context)
        let doomed = makeRoutine(store, name: "Doomed")
        let legs = makeRoutine(store, name: "Legs")
        let calendar = Self.calendar()
        let tuesday = try #require(calendar.date(byAdding: .day, value: 1, to: Self.monday()))

        var schedule = WeeklySchedule()
        schedule.addRoutine(doomed.id, to: .monday)
        schedule.addRoutine(legs.id, to: .monday)
        schedule.moved(date: tuesday, toRoutines: [doomed.id], calendar: calendar)
        store.saveSchedule(schedule)

        let program = ProgramModel(name: "Custom", weeks: 4)
        program.routineIDs = [doomed.id, legs.id]
        store.context.insert(program)
        store.save()

        store.deleteRoutine(id: doomed.id)

        let updated = store.schedule()
        #expect(updated.dayRoutines[.monday] == [legs.id])
        let overrideKey = DateKey.string(for: tuesday, calendar: calendar)
        #expect(updated.dateOverrides[overrideKey]?.isEmpty == true)
        #expect(store.programs().first { $0.id == program.id }?.routineIDs == [legs.id])
    }

    @Test("scheduleUpdatedAt tracks the last save")
    func scheduleUpdatedAtTracksSaves() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))
        #expect(store.scheduleUpdatedAt() == nil)
        store.saveSchedule(WeeklySchedule(dayRoutines: [.monday: [UUID()]]))
        #expect(store.scheduleUpdatedAt() != nil)
    }
}

extension WorkoutStore {
    /// Deletes only the `RoutineModel`, leaving every plan that points at it behind — the
    /// pre-fix state (and what a CloudKit merge from an older device can still produce). Tests
    /// only; `deleteRoutine` is what the app calls.
    func deleteRoutineModelOnly(id: UUID) {
        let descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id })
        guard let model = (try? context.fetch(descriptor))?.first else { return }
        context.delete(model)
        save()
    }
}

/// The rolling sync window, cross-device duplicates, the original day-only key format, and what
/// happens to a renamed or deleted routine's events. Uses `FakeEventStore` from
/// `CalendarSyncServiceTests`.
@Suite("Calendar sync window")
struct CalendarSyncWindowTests {
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar().date(from: components) ?? Date()
    }

    /// Monday 2026-01-05.
    private static func monday() -> Date { date(2026, 1, 5) }

    private func routine(name: String) -> RoutineInfo {
        RoutineInfo(
            name: name, exercises: [], setCount: 0, estimatedMinutes: 50, progressionRule: "linear",
            progressionDetail: ""
        )
    }

    private func request(
        schedule: WeeklySchedule, routines: [RoutineInfo], existingEventIDs: [String: String] = [:],
        startDate: Date = CalendarSyncWindowTests.monday(), days: Int = 7
    ) -> ScheduleSyncRequest {
        ScheduleSyncRequest(
            schedule: schedule, routines: routines, startDate: startDate, days: days,
            defaultStartHour: 18, existingEventIDs: existingEventIDs, calendar: Self.calendar()
        )
    }

    /// The defect: the sweep deleted every tracked key that wasn't re-planned, which included
    /// every day *before* `startDate` — so editing the schedule on the 22nd wiped the lifter's
    /// own calendar record of the 14th–21st.
    @Test("events before the sync window are kept, not deleted")
    func pastEventsSurvive() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        let calendar = Self.calendar()

        // Week 1: sync from Monday the 5th.
        let first = try await service.sync(request(schedule: schedule, routines: [pushA]))
        let pastKey = CalendarSyncService.eventKey(
            date: Self.monday(), routineID: pushA.id, calendar: calendar
        )
        let pastEventID = try #require(first[pastKey])

        // Week 2: the window has moved on to the 12th. The 5th is now in the past.
        let nextMonday = try #require(calendar.date(byAdding: .day, value: 7, to: Self.monday()))
        let second = try await service.sync(request(
            schedule: schedule, routines: [pushA], existingEventIDs: first, startDate: nextMonday
        ))

        #expect(fake.deletedIDs.isEmpty)
        #expect(second[pastKey] == pastEventID, "the past day's id must stay tracked")
        #expect(fake.events[pastEventID] != nil, "the past day's event must stay in the calendar")
    }

    @Test("event ids older than the retention horizon are forgotten without deleting their events")
    func ancientKeysArePrunedNotDeleted() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        let calendar = Self.calendar()
        let ancient = Self.date(2024, 1, 1)
        let ancientKey = CalendarSyncService.eventKey(
            date: ancient, routineID: pushA.id, calendar: calendar
        )

        let result = try await service.sync(request(
            schedule: schedule, routines: [pushA], existingEventIDs: [ancientKey: "ancient-event"]
        ))

        #expect(result[ancientKey] == nil)
        #expect(fake.deletedIDs.isEmpty, "history is the lifter's, not ours to delete")
    }

    @Test("a sync run later in the day still owns today's own event")
    func windowIsAnchoredToStartOfDay() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        let calendar = Self.calendar()
        let mondayEvening = try #require(
            calendar.date(byAdding: .hour, value: 21, to: Self.monday())
        )

        let result = try await service.sync(request(
            schedule: schedule, routines: [pushA], startDate: mondayEvening
        ))
        let mondayKey = CalendarSyncService.eventKey(
            date: Self.monday(), routineID: pushA.id, calendar: calendar
        )
        #expect(result[mondayKey] != nil)
    }

    // MARK: - Cross-device duplicates

    @Test("an untracked DaGym event in the window is collected, a user's own event is not")
    func orphanEventsAreReconciled() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        let calendar = Self.calendar()
        let mondaySix = try #require(calendar.date(byAdding: .hour, value: 18, to: Self.monday()))

        // What the losing device's sync leaves behind before CloudKit merges the two rows.
        let orphan = fake.plantOrphan(start: mondaySix, routineID: pushA.id)
        let mine = fake.plantUserEvent(start: mondaySix)

        _ = try await service.sync(request(schedule: schedule, routines: [pushA]))

        #expect(fake.deletedIDs.contains(orphan))
        #expect(fake.events[mine] != nil, "an event DaGym didn't write is never touched")
    }

    // MARK: - Key migration

    /// Before multi-routine days, the persisted map was keyed by calendar day alone. Those keys
    /// have to be adopted onto the day's first routine or the upgrade abandons every existing
    /// event and creates a duplicate next to it.
    @Test("legacy day-only keys are adopted onto the day's first routine")
    func legacyKeysMigrate() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        let arms = routine(name: "Arms")
        var schedule = WeeklySchedule()
        schedule.addRoutine(pushA.id, to: .monday)
        schedule.addRoutine(arms.id, to: .monday)
        let calendar = Self.calendar()
        let legacyKey = DateKey.string(for: Self.monday(), calendar: calendar)
        _ = try fake.upsertEvent(
            id: nil,
            draft: EventDraft(
                title: "DaGym · Push A", start: Self.monday(), end: Self.monday(), notes: "",
                url: URL(string: "dagym://start?routine=\(pushA.id.uuidString)")
            ),
            calendarID: "cal-0"
        )
        let legacyEventID = try #require(fake.events.keys.first)

        let result = try await service.sync(request(
            schedule: schedule, routines: [pushA, arms], existingEventIDs: [legacyKey: legacyEventID]
        ))

        let pushAKey = CalendarSyncService.eventKey(
            date: Self.monday(), routineID: pushA.id, calendar: calendar
        )
        #expect(result[pushAKey] == legacyEventID, "the existing event is re-used, not abandoned")
        #expect(result[legacyKey] == nil, "the legacy key is retired")
        #expect(fake.events.count == 2, "one re-used Push A event plus a new Arms event")
        #expect(fake.deletedIDs.isEmpty)
    }

    // MARK: - Renamed / deleted routines

    @Test("renaming a routine retitles its existing event rather than adding another")
    func renamingRetitlesTheSameEvent() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id

        let first = try await service.sync(request(schedule: schedule, routines: [pushA]))
        var renamed = pushA
        renamed.name = "Push (Heavy)"
        let second = try await service.sync(
            request(schedule: schedule, routines: [renamed], existingEventIDs: first)
        )

        #expect(second == first)
        #expect(fake.events.count == 1)
        #expect(fake.events.values.first?.title == "DaGym · Push (Heavy)")
    }

    @Test("a deleted routine's future events are removed once the schedule drops its id")
    func deletedRoutineEventsAreRemoved() async throws {
        let fake = FakeEventStore()
        let service = CalendarSyncService(eventStore: fake)
        let pushA = routine(name: "Push A")
        let legs = routine(name: "Legs")
        var schedule = WeeklySchedule()
        schedule.days[.monday] = pushA.id
        schedule.days[.wednesday] = legs.id

        let first = try await service.sync(request(schedule: schedule, routines: [pushA, legs]))
        #expect(first.count == 2)

        // `WorkoutStore.deleteRoutine` drops the id from the schedule; the routine is gone too.
        schedule.days[.monday] = nil
        let second = try await service.sync(
            request(schedule: schedule, routines: [legs], existingEventIDs: first)
        )

        #expect(second.count == 1)
        #expect(fake.events.count == 1)
        #expect(fake.events.values.first?.title == "DaGym · Legs")
    }
}
