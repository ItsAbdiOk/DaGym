import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore.recoverySnapshot")
struct WorkoutStoreRecoverySnapshotTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 20),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    @Test("3 completed chest sets make chest the most-spent muscle, recovering in the future")
    func chestIsMostSpentWithFutureRecovery() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true // warm-up: contributes nothing
        for index in 1...3 {
            session.exercises[0].sets[index].weightKg = 60
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)

        let snapshot = store.recoverySnapshot(now: Date())

        #expect(snapshot.perMuscle.first?.muscle == .chest)
        let chest = try #require(snapshot.perMuscle.first { $0.muscle == .chest })
        let recoveredBy = try #require(chest.recoveredBy)
        #expect(recoveredBy > Date())

        let contributor = try #require(chest.contributors.first)
        #expect(contributor.exerciseName == "Bench Press")
        #expect(contributor.sets == 3)
    }

    @Test("muscles with zero events in the last 7 days are listed as untrained")
    func untrainedMusclesHaveNoEvents() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 60
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let snapshot = store.recoverySnapshot(now: Date())

        #expect(!snapshot.untrainedMuscles.contains(.chest))
        #expect(snapshot.untrainedMuscles.contains(.calves))
        #expect(snapshot.untrainedMuscles.contains(.forearms))
    }
}
