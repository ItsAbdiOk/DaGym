import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Pins the fix for the N+1 that made `startWorkout` visibly stall on a many-exercise routine:
/// every exercise's progression baseline, ghost, last-sessions strip and sparkline used to
/// re-fetch the whole finished-workout list from the store separately. `finishedWorkoutsQueryCount`
/// (test-only instrumentation on `WorkoutStore`, bumped once per real `context.fetch` of that
/// list) lets this assert the query count stays bounded as the routine grows, instead of timing
/// wall-clock — which would be flaky under CI load.
@MainActor
@Suite("WorkoutStore start-workout query count")
struct WorkoutStoreStartPerformanceTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    /// Builds a routine with `count` exercises, each with a linear-progression rule and a couple
    /// of planned sets, then a few finished sessions of history behind it — the same shape
    /// `computeProgression`/`withHistoryStrip` read from for prescriptions, ghosts, the
    /// last-sessions strip and the sparkline.
    private func makeRoutineWithHistory(store: WorkoutStore, exerciseCount: Int) throws -> UUID {
        var drafts: [RoutineExerciseDraft] = []
        for index in 0..<exerciseCount {
            let exercise = store.createCustomExercise(
                name: "Exercise \(index)", primary: [.chest], equipment: "Barbell", style: .weightReps
            )
            drafts.append(RoutineExerciseDraft(
                exerciseID: exercise.id,
                sets: [
                    PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 40),
                    PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 40)
                ]
            ))
        }
        let routine = store.saveRoutine(
            id: nil, name: "Big Routine", progressionRule: "linear",
            rule: .linear(incrementKg: 2.5), exercises: drafts
        )

        // A few finished sessions of history per exercise, so progression, the ghost and the
        // history strip all have something real to read rather than the empty "first time" path.
        for _ in 0..<3 {
            let session = store.startWorkout(routineID: routine.id)
            for index in session.exercises.indices {
                for setIndex in session.exercises[index].sets.indices {
                    session.exercises[index].sets[setIndex].weightKg = 40
                    session.exercises[index].sets[setIndex].reps = 8
                    session.exercises[index].sets[setIndex].isDone = true
                }
            }
            _ = store.finish(session: session)
        }
        return routine.id
    }

    @Test("starting an 8-exercise routine issues a bounded number of finished-workout queries")
    func startWorkoutQueryCountIsBounded() throws {
        let store = try makeStore()
        let routineID = try makeRoutineWithHistory(store: store, exerciseCount: 8)

        store.discard(session: store.startWorkout(routineID: routineID)) // warm-up, not measured
        let before = store.finishedWorkoutsQueryCount
        let session = store.startWorkout(routineID: routineID)
        let queries = store.finishedWorkoutsQueryCount - before

        #expect(session.exercises.count == 8)
        // The old N+1 shape issued ~4 queries per exercise (progression baseline, ghost,
        // last-sessions strip, sparkline) — 32+ for 8 exercises. Batched, it's one fetch for the
        // whole routine regardless of size; allow a little headroom without re-opening the door
        // to per-exercise scaling.
        #expect(queries <= 2, "expected a bounded query count, got \(queries) for 8 exercises")
    }

    @Test("query count does not scale with routine size")
    func startWorkoutQueryCountDoesNotScaleWithExerciseCount() throws {
        let smallStore = try makeStore()
        let smallRoutineID = try makeRoutineWithHistory(store: smallStore, exerciseCount: 2)
        smallStore.discard(session: smallStore.startWorkout(routineID: smallRoutineID))
        let smallBefore = smallStore.finishedWorkoutsQueryCount
        _ = smallStore.startWorkout(routineID: smallRoutineID)
        let smallQueries = smallStore.finishedWorkoutsQueryCount - smallBefore

        let bigStore = try makeStore()
        let bigRoutineID = try makeRoutineWithHistory(store: bigStore, exerciseCount: 12)
        bigStore.discard(session: bigStore.startWorkout(routineID: bigRoutineID))
        let bigBefore = bigStore.finishedWorkoutsQueryCount
        _ = bigStore.startWorkout(routineID: bigRoutineID)
        let bigQueries = bigStore.finishedWorkoutsQueryCount - bigBefore

        #expect(
            smallQueries == bigQueries,
            "query count grew with exercise count: \(smallQueries) vs \(bigQueries)"
        )
    }
}
