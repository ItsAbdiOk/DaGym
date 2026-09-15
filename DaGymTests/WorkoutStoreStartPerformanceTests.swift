import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Pins the fix for the N+1s in the session-building paths: every exercise used to re-derive
/// facts that belong to the *session* — the finished-workout list, the equipment profile, the
/// latest bodyweight, the active program's week and cycle, the PR cache — each costing its own
/// round trip to the store. `WorkoutStore.queryCount` counts every SwiftData read the store
/// issues (they all funnel through `fetch`/`fetchFirst`/`fetchCount`), so these tests can assert
/// the real query count rather than one instrumented helper's.
///
/// The load-bearing assertion in each test is `small == big`: a 2-exercise and a 12-exercise
/// routine must issue the *same* number of queries. "Under some constant" would pass with a
/// per-exercise query still in place; equality cannot. No wall-clock assertions — they'd be
/// flaky under CI load.
@MainActor
@Suite("WorkoutStore session-build query counts")
struct WorkoutStoreStartPerformanceTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    /// Builds a routine with `count` exercises, each with a linear-progression rule and a couple
    /// of planned sets, then a few finished sessions of history behind it — the same shape
    /// `computeProgression`/`withHistoryStrip` read from for prescriptions, ghosts, the
    /// last-sessions strip and the sparkline.
    private func makeRoutineWithHistory(store: WorkoutStore, exerciseCount: Int) -> UUID {
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

    /// Runs `body` against a freshly seeded store of `exerciseCount` exercises and reports how
    /// many queries it issued — the setup itself is never measured.
    private func queries(
        exerciseCount: Int, _ body: (WorkoutStore, UUID) -> Void
    ) throws -> Int {
        let store = try makeStore()
        let routineID = makeRoutineWithHistory(store: store, exerciseCount: exerciseCount)
        let before = store.queryCount
        body(store, routineID)
        return store.queryCount - before
    }

    /// `small == big` for one path, plus the count itself so a regression report says what it
    /// actually cost.
    private func expectFlat(
        _ label: String, _ body: (WorkoutStore, UUID) -> Void
    ) throws -> Int {
        let small = try queries(exerciseCount: 2, body)
        let big = try queries(exerciseCount: 12, body)
        #expect(
            small == big,
            "\(label): query count grew with exercise count — \(small) for 2, \(big) for 12"
        )
        return big
    }

    @Test("startWorkout issues the same number of queries for 2 and for 12 exercises")
    func startWorkoutQueryCountDoesNotScale() throws {
        let count = try expectFlat("startWorkout") { store, routineID in
            _ = store.startWorkout(routineID: routineID)
        }
        // Exactly: the routine, the finished-workout list, the per-exercise session counts (one
        // fetch with the exercise prefetched — it used to walk `workout.exercises` and fire a
        // SwiftData fault per row, ~1 000 hidden round trips on a real history that this counter
        // never saw), the equipment profile, the latest bodyweight, the PR cache, and the active
        // program (whose own lookup is two). The old
        // shape added ~10 per exercise on top — equipment, bodyweight, two `activeProgramModel`
        // pairs, the PR row, the session count and two `ExerciseModel` fetches for the history
        // strip — so an 8-exercise routine cost 80+. Exact, not a ceiling: a new constant query
        // on this path should be a deliberate change, not a silent one.
        #expect(count == 8, "startWorkout issued \(count) queries for a 12-exercise routine")
    }

    @Test("an 8-exercise routine starts in a handful of queries, and all 8 exercises are built")
    func startWorkoutOnEightExercises() throws {
        let store = try makeStore()
        let routineID = makeRoutineWithHistory(store: store, exerciseCount: 8)
        let before = store.queryCount
        let session = store.startWorkout(routineID: routineID)
        #expect(session.exercises.count == 8)
        #expect(store.queryCount - before == 8)
    }

    @Test("appendRoutine issues the same number of queries for 2 and for 12 exercises")
    func appendRoutineQueryCountDoesNotScale() throws {
        let count = try expectFlat("appendRoutine") { store, routineID in
            let session = store.startFreestyle()
            store.appendRoutine(id: routineID, to: session)
        }
        // The build above (8) plus `sync`: the workout, one batched library-exercise
        // lookup for the new rows, and the routine their exclusion flags come from.
        #expect(count == 12, "appendRoutine issued \(count) queries for a 12-exercise routine")
    }

    @Test("resumeSession issues the same number of queries for 2 and for 12 exercises")
    func resumeSessionQueryCountDoesNotScale() throws {
        let count = try expectFlat("resumeSession") { store, routineID in
            let session = store.startWorkout(routineID: routineID)
            store.sync(session: session)
            guard let workoutID = session.workoutID else { return }
            let resumed = store.resumeSession(for: workoutID)
            #expect(resumed?.exercises.count == session.exercises.count)
        }
        // `startWorkout` (8) and `sync` (3) are setup inside the body; `resumeSession`
        // itself is the remaining 9 — the workout, its session facts, and the routine
        // behind the glyph.
        #expect(count == 20, "resumeSession issued \(count) queries for a 12-exercise routine")
    }

    /// Adding one exercise mid-workout is a per-add cost by nature, so what must not scale here
    /// is the size of the session it is added to — and, with it, the amount of history behind it.
    @Test("adding an exercise mid-workout costs the same in a 2- and a 12-exercise session")
    func autoFilledEntryQueryCountDoesNotScale() throws {
        let count = try expectFlat("autoFilledEntry") { store, routineID in
            let session = store.startWorkout(routineID: routineID)
            guard let existing = session.exercises.first?.exercise else { return }
            session.exercises.append(store.autoFilledEntry(for: existing))
        }
        // `startWorkout` (8) is setup inside the body; the add itself is 5 — one session
        // facts build. It was 6, four of them repeats of the finished-workout list.
        #expect(count == 13, "one mid-workout add issued \(count) queries")
    }
}
