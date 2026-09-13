import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore history detail")
struct WorkoutStoreHistoryDetailTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    @Test("lifetimeStats sums only finished workouts, excluding warm-up volume")
    func lifetimeStatsSumsFinishedWorkouts() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let first = store.startWorkout(routineID: routineID)
        first.exercises[0].sets[0].isDone = true
        first.exercises[0].sets[1].weightKg = 60
        first.exercises[0].sets[1].reps = 8
        first.exercises[0].sets[1].isDone = true
        _ = store.finish(session: first)

        let second = store.startWorkout(routineID: routineID)
        second.exercises[0].sets[1].weightKg = 70
        second.exercises[0].sets[1].reps = 5
        second.exercises[0].sets[1].isDone = true
        _ = store.finish(session: second)

        _ = store.startWorkout(routineID: routineID)

        let stats = store.lifetimeStats()
        #expect(stats.workouts == 2)
        #expect(stats.volumeKg == 60 * 8 + 70 * 5)
    }

    @Test("workoutDetail returns exercises, sets and PR count for a finished workout")
    func workoutDetailReturnsFullBreakdown() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Deadlift", primary: [.hams], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true
        session.exercises[0].sets[1].weightKg = 120
        session.exercises[0].sets[1].reps = 5
        session.exercises[0].sets[1].isDone = true
        let summary = store.finish(session: session)

        guard let workoutID = session.workoutID else {
            Issue.record("session missing workoutID")
            return
        }
        let detail = store.workoutDetail(id: workoutID)

        #expect(detail.exercises.map(\.exercise.name) == ["Deadlift"])
        #expect(detail.exercises.first?.sets.count == 2)
        #expect(detail.setsDone == 1) // the warm-up doesn't count, matching the recap and Health
        #expect(detail.volumeKg == 120 * 5)
        #expect(detail.prCount == summary.prs.count)
        #expect(detail.isBackfilled == false)
    }
}
