import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// OpenGym parity (insights rec 4): balance windows and the hard-set filter on `bodySeries`.
@MainActor
@Suite("Parity: balance windows")
struct ParityInsightsSeriesTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
    }

    private func makeRoutine(store: WorkoutStore, exerciseID: UUID, rpes: [Double?]) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: rpes.map { _ in PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60) }
        )
        return store.saveRoutine(id: nil, name: "Day", exercises: [draft]).id
    }

    private func logSession(_ store: WorkoutStore, routineID: UUID, at date: Date, rpes: [Double?]) throws {
        let session = store.startWorkout(routineID: routineID)
        for (index, rpe) in rpes.enumerated() {
            session.exercises[0].sets[index].weightKg = 60
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].effort = rpe.map { Effort(rpe: $0) }
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)
        let workoutID = try #require(session.workoutID)
        let workout = try #require(store.fetchWorkoutModel(id: workoutID))
        workout.startedAt = date
        workout.endedAt = date.addingTimeInterval(3600)
        for exercise in workout.exercises ?? [] {
            for set in exercise.sets ?? [] { set.completedAt = date }
        }
        store.save()
    }

    @Test("thisWeek: Monday-start counts only Wednesday's session; Sunday-start counts Sunday's too")
    func thisWeekHonoursTrainingCalendar() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: bench.id, rpes: [nil])
        // 2024-01-07 is a Sunday, 2024-01-10 a Wednesday.
        try logSession(store, routineID: routineID, at: date("2024-01-07T10:00:00Z"), rpes: [nil])
        try logSession(store, routineID: routineID, at: date("2024-01-10T10:00:00Z"), rpes: [nil])
        let now = date("2024-01-10T20:00:00Z")

        let monday = calendar(firstWeekday: 2)
        let mondayBundle = store.bodySeries(
            weeks: 8, calendar: monday, balanceWindow: .thisWeek(monday), now: now
        )
        #expect(mondayBundle.setsPerMuscle[.chest] == 1)

        let sunday = calendar(firstWeekday: 1)
        let sundayBundle = store.bodySeries(
            weeks: 8, calendar: sunday, balanceWindow: .thisWeek(sunday), now: now
        )
        #expect(sundayBundle.setsPerMuscle[.chest] == 2)
    }

    @Test("hardOnly: 4 chest sets at RIR 4 + 1 at RIR 0 → chest = 1")
    func hardOnlyCountsNearFailureSets() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let rpes: [Double?] = [6, 6, 6, 6, 10]
        let routineID = makeRoutine(store: store, exerciseID: bench.id, rpes: rpes)
        let now = date("2024-01-10T20:00:00Z")
        try logSession(store, routineID: routineID, at: date("2024-01-10T10:00:00Z"), rpes: rpes)

        let hard = store.bodySeries(weeks: 8, calendar: calendar(firstWeekday: 2), hardOnly: true, now: now)
        #expect(hard.setsPerMuscle[.chest] == 1)
        let all = store.bodySeries(weeks: 8, calendar: calendar(firstWeekday: 2), now: now)
        #expect(all.setsPerMuscle[.chest] == 5)
    }

    @Test("allTime reaches past the chart's weeks window; days(30) stops at 30")
    func allTimeAndThirtyDays() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: bench.id, rpes: [nil, nil])
        let now = date("2024-06-01T12:00:00Z")
        for daysAgo in [1, 20, 40, 100] {
            try logSession(
                store, routineID: routineID, at: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                rpes: [nil, nil]
            )
        }
        let calendar = calendar(firstWeekday: 2)
        let allTime = store.bodySeries(weeks: 8, calendar: calendar, balanceWindow: .allTime, now: now)
        #expect(allTime.setsPerMuscle[.chest] == 8)
        let month = store.bodySeries(weeks: 8, calendar: calendar, balanceWindow: .days(30), now: now)
        #expect(month.setsPerMuscle[.chest] == 4)
        let week = store.bodySeries(weeks: 8, calendar: calendar, now: now)
        #expect(week.setsPerMuscle[.chest] == 2)
    }

    // MARK: - Muscle map modes

    @Test("ratedSetsInWindow: unrated sessions leave the hard-only map with nothing to say")
    func ratedSetsFollowTheWindow() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: bench.id, rpes: [nil, nil])
        let now = date("2024-06-01T12:00:00Z")
        try logSession(store, routineID: routineID, at: date("2024-05-31T10:00:00Z"), rpes: [nil, nil])
        try logSession(store, routineID: routineID, at: date("2024-04-01T10:00:00Z"), rpes: [8, nil])
        let calendar = calendar(firstWeekday: 2)
        let hard = { (window: BalanceWindow) in
            store.bodySeries(weeks: 1, calendar: calendar, balanceWindow: window, hardOnly: true, now: now)
        }
        #expect(hard(.days(7)).ratedSetsInWindow == 0)
        #expect(hard(.days(7)).setsPerMuscle[.chest] == nil)
        #expect(hard(.allTime).ratedSetsInWindow == 1)
        #expect(hard(.allTime).setsPerMuscle[.chest] == 1)
        // An empty store has an empty window, not zeros per muscle.
        let fresh = try makeStore()
        let empty = fresh.bodySeries(weeks: 1, calendar: calendar, balanceWindow: .allTime, now: now)
        #expect(empty.setsPerMuscle.isEmpty)
        #expect(empty.ratedSetsInWindow == 0)
    }

    @Test("muscleStrength: top lifts per primary mover from the PR cache; empty store is empty")
    func muscleStrengthFromRecords() throws {
        let store = try makeStore()
        #expect(store.muscleStrength().isEmpty)
        let bench = store.createCustomExercise(
            name: "Bench", primary: [.chest, .triceps], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: bench.id, rpes: [nil])
        try logSession(store, routineID: routineID, at: date("2024-05-31T10:00:00Z"), rpes: [nil])
        let top = store.muscleStrength()
        let chest = try #require(top[.chest]?.first)
        #expect(chest.name == "Bench")
        #expect(chest.exerciseID == bench.id)
        // 60 kg × 8 → the same e1RM the PR cache holds, never a second estimate.
        #expect(abs(chest.e1rmKg - (store.bestE1RMRecord(exerciseID: bench.id)?.value ?? 0)) < 0.001)
        #expect(top[.triceps]?.first?.name == "Bench")
        #expect(top[.quads] == nil)
    }
}
