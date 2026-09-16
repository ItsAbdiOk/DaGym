import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Fixtures shared by the two optimisation-pass suites (`DataOptimisationTests`,
/// `DataOptimisationMoreTests`).
@MainActor
struct DataOptimisationFixtures {
    func makeBench(_ store: WorkoutStore) -> ExerciseInfo {
        store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
    }

    func makeRoutine(_ store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    /// Finishes `count` sessions at rising weights so each sets a PR.
    @discardableResult
    func logSessions(
        _ store: WorkoutStore, routineID: UUID, count: Int, from weightKg: Double = 60
    ) -> [UUID] {
        (0..<count).compactMap { index in
            let session = store.startWorkout(routineID: routineID)
            for setIndex in session.exercises[0].sets.indices {
                session.exercises[0].sets[setIndex].weightKg = weightKg + Double(index) * 5
                session.exercises[0].sets[setIndex].reps = 8
                session.exercises[0].sets[setIndex].isDone = true
            }
            _ = store.finish(session: session)
            return session.workoutID
        }
    }

    func queries(_ store: WorkoutStore, _ body: () -> Void) -> Int {
        let before = store.queryCount
        body()
        return store.queryCount - before
    }

    // MARK: - Exercise catalogue cache

}
