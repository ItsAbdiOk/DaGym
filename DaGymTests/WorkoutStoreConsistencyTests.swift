import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore consistency + weekly recap")
struct WorkoutStoreConsistencyTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 20),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    /// Finishes a workout with one completed working set (60kg x 8), backdated by `daysAgo`.
    @discardableResult
    private func finishWorkout(store: WorkoutStore, routineID: UUID, daysAgo: Int) -> WorkoutSession {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let session = daysAgo == 0
            ? store.startWorkout(routineID: routineID)
            : store.startBackfill(date: date, durationMinutes: 40, routineID: routineID)
        session.exercises[0].sets[1].weightKg = 60
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)
        return session
    }

    @Test("consistencyCells has one cell per day, with sets on the days workouts happened")
    func consistencyCellsCoversRange() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)
        finishWorkout(store: store, routineID: routineID, daysAgo: 3)

        let cells = store.consistencyCells(months: 1)
        #expect(cells.count > 25) // at least a month of days
        let activeDay = cells.first { $0.sets > 0 }
        #expect(activeDay?.sets == 1)
        #expect(activeDay?.level == 4) // the only active day, so it's its own busiest
    }

    @Test("weeklyRecap totals this week's workouts, sets, volume and PRs")
    func weeklyRecapTotals() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)
        finishWorkout(store: store, routineID: routineID, daysAgo: 0)

        let recap = store.weeklyRecap(for: Date(), weeklyGoal: 4)
        #expect(recap.workouts == 1)
        #expect(recap.sets == 1)
        #expect(recap.volumeKg == 480) // 60kg x 8 reps
        #expect(recap.prs == 1) // first-ever e1RM for this exercise
        #expect(recap.weeklyGoal == 4)
    }

    @Test("weeklyRecap compares against last week, not two weeks ago")
    func weeklyRecapDeltaVsLastWeek() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)
        finishWorkout(store: store, routineID: routineID, daysAgo: 0) // this week
        finishWorkout(store: store, routineID: routineID, daysAgo: 7) // last week
        finishWorkout(store: store, routineID: routineID, daysAgo: 20) // outside the comparison

        let recap = store.weeklyRecap(for: Date(), weeklyGoal: 4)
        #expect(recap.workouts == 1)
        #expect(recap.workoutsDelta == 0) // 1 this week vs 1 last week
    }
}
