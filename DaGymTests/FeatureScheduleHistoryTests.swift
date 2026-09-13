import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// OpenGym feature batch B2: multi-routine schedule days, "add routine to session", the month
/// calendar model, backfill conflicts and undo-able workout deletion.
@MainActor
@Suite("Feature: schedule & history")
struct FeatureScheduleHistoryTests {
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

    private static func date(_ day: Int, month: Int = 1) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = 10
        return calendar().date(from: components) ?? Date()
    }

    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(_ store: WorkoutStore, name: String, exercises: Int = 1) -> RoutineInfo {
        let drafts = (0..<exercises).map { index in
            let exercise = store.createCustomExercise(
                name: "\(name) Exercise \(index)", primary: [.chest], equipment: "Barbell", style: .weightReps
            )
            return RoutineExerciseDraft(
                exerciseID: exercise.id,
                sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
            )
        }
        return store.saveRoutine(id: nil, name: name, exercises: drafts)
    }

    // MARK: - Item 7: multiple routines per day

    @Test("todaysRoutines returns the day's routines in schedule order")
    func todaysRoutinesInOrder() throws {
        let store = try makeStore()
        let pushA = makeRoutine(store, name: "Push A")
        let arms = makeRoutine(store, name: "Arms")
        var schedule = WeeklySchedule()
        schedule.addRoutine(arms.id, to: .monday)
        schedule.addRoutine(pushA.id, to: .monday)
        store.saveSchedule(schedule)

        let planned = store.todaysRoutines(calendar: Self.calendar(), now: Self.monday())
        #expect(planned.map(\.name) == ["Arms", "Push A"])
        #expect(store.todaysRoutine(calendar: Self.calendar(), now: Self.monday())?.name == "Arms")
        let saved = store.schedule().routineIDs(on: Self.monday(), calendar: Self.calendar())
        #expect(saved == [arms.id, pushA.id])
    }

    @Test("appendRoutine adds the routine's exercises after the current ones and combines the title")
    func appendRoutineMergesExercises() throws {
        let store = try makeStore()
        let pushA = makeRoutine(store, name: "Push A", exercises: 2)
        let arms = makeRoutine(store, name: "Arms", exercises: 1)

        let session = store.startWorkout(routineID: pushA.id)
        store.appendRoutine(id: arms.id, to: session)

        #expect(session.exercises.count == 3)
        #expect(session.exercises.last?.exercise.name == "Arms Exercise 0")
        #expect(session.exercises.last?.sets.first?.reps == 8)
        #expect(session.title == "Push A + Arms")
        let model = try #require(session.workoutID.flatMap(store.workout(id:)))
        #expect(model.title == "Push A + Arms")
        #expect(model.routineName == "Push A + Arms")
        #expect(model.routineID == pushA.id)
        #expect(model.exercises?.count == 3)

        store.appendRoutine(id: arms.id, to: session)
        #expect(session.title == "Push A + Arms")
        #expect(session.exercises.count == 4)
    }

    @Test("appendRoutine on a freestyle session names it after the routine; unknown ids are ignored")
    func appendRoutineToFreestyle() throws {
        let store = try makeStore()
        let arms = makeRoutine(store, name: "Arms")
        let session = store.startFreestyle()

        store.appendRoutine(id: UUID(), to: session)
        #expect(session.exercises.isEmpty)
        #expect(session.title == "Freestyle")

        store.appendRoutine(id: arms.id, to: session)
        #expect(session.title == "Arms")
        #expect(session.exercises.count == 1)
    }

    @Test("startWorkout(routineIDs:) merges every routine in order; an empty list is freestyle")
    func startWorkoutWithRoutineIDs() throws {
        let store = try makeStore()
        let pushA = makeRoutine(store, name: "Push A", exercises: 2)
        let arms = makeRoutine(store, name: "Arms", exercises: 1)

        let merged = store.startWorkout(routineIDs: [pushA.id, arms.id])
        #expect(merged.exercises.map(\.exercise.name) == [
            "Push A Exercise 0", "Push A Exercise 1", "Arms Exercise 0"
        ])
        #expect(merged.title == "Push A + Arms")

        let freestyle = store.startWorkout(routineIDs: [])
        #expect(freestyle.exercises.isEmpty)
        #expect(freestyle.title == "Freestyle")
    }

    // MARK: - Item 8: month calendar model

    @Test("month model marks trained, planned and rescheduled days and pads to the first weekday")
    func monthCalendarModel() throws {
        let store = try makeStore()
        let pushA = makeRoutine(store, name: "Push A")
        let legs = makeRoutine(store, name: "Legs")
        let calendar = Self.calendar()
        var schedule = WeeklySchedule()
        schedule.addRoutine(pushA.id, to: .monday)
        schedule.addRoutine(legs.id, to: .monday)
        schedule.moved(date: Self.date(12), toRoutines: [], calendar: calendar)
        schedule.moved(date: Self.date(13), toRoutines: [legs.id], calendar: calendar)

        let session = store.startBackfill(date: Self.date(5), durationMinutes: 45, routineID: pushA.id)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
        let records = store.history()

        let model = MonthCalendarModel(
            month: Self.date(20), records: records, schedule: schedule, routines: store.routines(),
            calendar: calendar, now: Self.date(20)
        )
        // January 2026 starts on a Thursday; Monday-first week → 3 blanks.
        #expect(model.leadingBlanks == 3)
        #expect(model.days.count == 31)
        let byDay = Dictionary(uniqueKeysWithValues: model.days.map { ($0.dayNumber, $0) })
        #expect(byDay[5]?.workoutID == records.first?.id)
        #expect(byDay[5]?.title == "Push A")
        #expect(byDay[19]?.plannedRoutineIDs == [pushA.id, legs.id])
        #expect(byDay[19]?.title == "Push A + Legs")
        #expect(byDay[19]?.isRescheduled == false)
        #expect(byDay[12]?.state == .free)
        #expect(byDay[13]?.plannedRoutineIDs == [legs.id])
        #expect(byDay[13]?.isRescheduled == true)
        #expect(byDay[20]?.isToday == true)
        #expect(byDay[19]?.isPast == true)
        #expect(byDay[26]?.isPast == false)
        #expect(model.trainedCount == 1)
        #expect(model.plannedCount == 3)
    }

    // MARK: - Item 11: backfill conflict

    @Test("a backfill on a day that already has a workout finds it; other days are free")
    func backfillConflictDetection() throws {
        let store = try makeStore()
        let pushA = makeRoutine(store, name: "Push A")
        let calendar = Self.calendar()
        let session = store.startBackfill(date: Self.date(5), durationMinutes: 45, routineID: pushA.id)
        _ = store.finish(session: session)
        let records = store.history()

        let sameDay = Self.date(5).addingTimeInterval(3 * 3600)
        let existing = BackfillConflict.workouts(on: sameDay, in: records, calendar: calendar)
        #expect(existing.map(\.id) == records.map(\.id))
        #expect(BackfillConflict.workouts(on: Self.date(6), in: records, calendar: calendar).isEmpty)
        #expect(BackfillConflict.message(for: existing).hasPrefix("Push A is already logged"))
        #expect(BackfillConflict.message(for: existing + existing).hasPrefix("2 workouts are already logged"))
    }

    @Test("Replace deletes the day's workouts; Keep both leaves them")
    func backfillReplaceKeepsOrDeletes() throws {
        let store = try makeStore()
        let pushA = makeRoutine(store, name: "Push A")
        let first = store.startBackfill(date: Self.date(5), durationMinutes: 45, routineID: pushA.id)
        _ = store.finish(session: first)
        let existing = store.history().map(\.id)

        // Keep both: second workout lands beside the first.
        let second = store.startBackfill(date: Self.date(5), durationMinutes: 30, routineID: nil)
        _ = store.finish(session: second)
        #expect(store.history().count == 2)

        // Replace: the caller deletes what the conflict listed, then logs the new one.
        for id in existing {
            store.deleteWorkout(id: id)
        }
        let third = store.startBackfill(date: Self.date(5), durationMinutes: 30, routineID: pushA.id)
        _ = store.finish(session: third)
        #expect(store.history().count == 2)
        #expect(!store.history().map(\.id).contains(existing[0]))
    }

    // MARK: - Item 23: undo delete

    @Test("deleteWorkout hands back a snapshot that restoreWorkout puts back with the same ids and sets")
    func deleteAndRestoreWorkout() throws {
        let store = try makeStore()
        let pushA = makeRoutine(store, name: "Push A", exercises: 2)
        let session = store.startWorkout(routineID: pushA.id)
        session.exercises[0].sets[0].weightKg = 80
        session.exercises[0].sets[0].reps = 5
        session.exercises[0].sets[0].isDone = true
        session.exercises[0].note = "felt heavy"
        session.notes = "Good day"
        _ = store.finish(session: session)
        let workoutID = try #require(session.workoutID)
        let before = store.workoutDetail(id: workoutID)
        let setID = try #require(before.exercises.first?.sets.first?.id)
        #expect(store.personalRecords().isEmpty == false)

        let snapshot = try #require(store.deleteWorkout(id: workoutID))
        #expect(store.history().isEmpty)
        #expect(store.workout(id: workoutID) == nil)
        #expect(store.personalRecords().isEmpty)

        store.restoreWorkout(snapshot)
        let after = store.workoutDetail(id: workoutID)
        #expect(store.history().count == 1)
        #expect(after.title == before.title)
        #expect(after.notes == "Good day")
        #expect(after.endedAt == before.endedAt)
        #expect(after.exercises.map(\.exercise.name) == before.exercises.map(\.exercise.name))
        #expect(after.exercises.first?.sets.first?.id == setID)
        #expect(after.exercises.first?.sets.first?.weightKg == 80)
        #expect(after.exercises.first?.sets.first?.isDone == true)
        // The second exercise had no completed sets, so `finish` dropped it from history.
        #expect(after.exercises.count == 1)
        #expect(after.exercises.first?.note == "felt heavy")
        #expect(store.personalRecords().isEmpty == false)

        // Restoring twice is a no-op.
        store.restoreWorkout(snapshot)
        #expect(store.history().count == 1)
    }

    @Test("deleting an unknown workout returns nil")
    func deleteUnknownWorkout() throws {
        let store = try makeStore()
        #expect(store.deleteWorkout(id: UUID()) == nil)
    }
}
