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

    @Test("3 completed all-out chest sets make chest the most-spent muscle, recovering in the future")
    func chestIsMostSpentWithFutureRecovery() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true // warm-up: contributes nothing
        // RIR 0 → effort 1.0 each, fatigue 3.0 → 33 % spent, just over the 30 % "still spent"
        // line. Three sets of unknown effort (0.75 each) would sit at 27 % — already "fresh",
        // so `recoveredBy` is nil by design (same line `Recovery.headline` uses).
        for index in 1...3 {
            session.exercises[0].sets[index].weightKg = 60
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].effort = Effort(rpe: 10)
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

    @Test("a muscle already under the headline threshold reports no recoveredBy (it's fresh)")
    func underThresholdMuscleIsFreshNow() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        // Three sets with no effort logged: 3 × 0.75 = 2.25 fatigue → 27 % spent < 30 %.
        for index in 1...3 {
            session.exercises[0].sets[index].weightKg = 60
            session.exercises[0].sets[index].reps = 8
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)

        let chest = try #require(store.recoverySnapshot(now: Date()).perMuscle.first { $0.muscle == .chest })
        #expect(chest.spent < TrainingConstants.recoveryHeadlineThreshold)
        #expect(chest.recoveredBy == nil)
    }

    @Test("recoveredBy is derived from Recovery.fatigueThreshold, not the pre-normalisation formula")
    func recoveredByMatchesFatigueThresholdFormula() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let sets = (0..<10).map { _ in PlannedSetDraft(kind: .working, targetReps: 5, targetWeightKg: 80) }
        let draft = RoutineExerciseDraft(exerciseID: exercise.id, sets: sets)
        let routineID = store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id

        let session = store.startWorkout(routineID: routineID)
        for index in 0..<10 {
            session.exercises[0].sets[index].weightKg = 80
            session.exercises[0].sets[index].reps = 5
            session.exercises[0].sets[index].effort = Effort(rpe: 8) // RIR 2
            session.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: session)

        let now = Date()
        let snapshot = store.recoverySnapshot(now: now)
        let chest = try #require(snapshot.perMuscle.first { $0.muscle == .chest })
        let recoveredBy = try #require(chest.recoveredBy)

        let expectedThreshold = Recovery.fatigueThreshold(spent: TrainingConstants.recoveryHeadlineThreshold)
        let expectedInterval = Recovery.recoveredBy(
            fatigue: chest.fatigue, tau: Muscle.chest.recoveryTimeConstantHours, threshold: expectedThreshold
        )
        let expectedDate = now.addingTimeInterval(expectedInterval)
        #expect(abs(recoveredBy.timeIntervalSince(expectedDate)) < 1)
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
