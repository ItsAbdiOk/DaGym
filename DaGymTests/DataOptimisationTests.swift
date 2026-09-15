import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Pins the optimisation pass over the store's history-scaling paths: the cached exercise
/// catalogue, the grouped PR counts behind `history()`, the stamped per-workout totals behind
/// `lifetimeStats()`, the single finished-list read `finish()` threads through, the in-memory PR
/// rebuild, the one-query Siri lookup, and the rest-timer/totals split of `WorkoutSession`.
/// Query counts, never wall-clock: `WorkoutStore.queryCount` counts every store read.
@MainActor
@Suite("Data optimisation pass")
struct DataOptimisationTests {
    private let fx = DataOptimisationFixtures()

    @Test("a second library search between saves reads the store zero times")
    func catalogueIsCachedBetweenSaves() throws {
        let store = try fx.makeStore()
        let bench = fx.makeBench(store)
        #expect(fx.queries(store) { _ = store.exercises(matching: "ben") } == 2)
        // Library and PR cache were read for the first search; the next keystroke reads nothing.
        #expect(fx.queries(store) { _ = store.exercises(matching: "bench") } == 0)
        #expect(fx.queries(store) { _ = store.exerciseCount() } == 0)
        #expect(store.exerciseCount() == 1)

        // A save moves the token: the next read sees the new row.
        store.createCustomExercise(name: "Row", primary: [.lats], equipment: "Barbell", style: .weightReps)
        #expect(store.exerciseCount() == 2)
        store.toggleFavorite(id: bench.id)
        #expect(store.exercises().first?.isFavorite == true)
    }

    @Test("dedupeSeededRows drops the cached catalogue even when it saves nothing")
    func remoteFoldInvalidatesCatalogue() throws {
        let store = try fx.makeStore()
        _ = store.exercises()
        // A row inserted and saved behind the store's back, the way a CloudKit import lands.
        store.context.insert(
            ExerciseModel(name: "Remote Curl", primaryMuscles: ["biceps"], equipment: "Dumbbell")
        )
        try store.context.save()
        #expect(store.exerciseCount() == 0, "the stale catalogue is served until something invalidates it")
        store.dedupeSeededRows()
        #expect(store.exerciseCount() == 1)
    }

    // MARK: - history() and lifetimeStats()

    @Test("history() issues the same number of queries for 2 and for 6 finished workouts")
    func historyQueryCountDoesNotScale() throws {
        var counts: [Int] = []
        for workouts in [2, 6] {
            let store = try fx.makeStore()
            let routineID = fx.makeRoutine(store, exerciseID: fx.makeBench(store).id)
            fx.logSessions(store, routineID: routineID, count: workouts)
            let records = store.history()
            #expect(records.count == workouts)
            #expect(records.allSatisfy { $0.prCount == 1 })
            counts.append(fx.queries(store) { _ = store.history() })
        }
        // Exactly: the workouts (exercise rows prefetched) and the grouped PR events. It was
        // 1 + N `fetchCount`s for the PR badges.
        #expect(counts == [2, 2], "history() issued \(counts) queries for 2 and 6 workouts")
    }

    @Test("finish() stamps volume and sets on the workout, and lifetimeStats reads the column")
    func finishStampsTotals() throws {
        let store = try fx.makeStore()
        let bench = fx.makeBench(store)
        let routineID = fx.makeRoutine(store, exerciseID: bench.id)
        let ids = fx.logSessions(store, routineID: routineID, count: 2)
        let firstID = try #require(ids.first)
        let first = try #require(store.workout(id: firstID))
        // The warm-up is excluded from both, as the History row excludes it.
        #expect(first.volumeKg == 60 * 8)
        #expect(first.setsDone == 1)
        #expect(first.hasStampedTotals)

        let stats = store.lifetimeStats()
        #expect(stats.workouts == 2)
        #expect(stats.volumeKg == 60 * 8 + 65 * 8)
        // One column fetch (plus the Health-store count, which isn't a main-store query) —
        // never a walk of every set, and never the seed row: the backfill runs at launch.
        #expect(fx.queries(store) { _ = store.lifetimeStats() } == 1)
    }

    @Test("workouts finished before the totals columns existed are stamped once, at launch")
    func totalsBackfillRunsOnce() throws {
        let store = try fx.makeStore()
        let routineID = fx.makeRoutine(store, exerciseID: fx.makeBench(store).id)
        let ids = fx.logSessions(store, routineID: routineID, count: 3)
        // Simulate rows written by a build without the columns: zero totals, flag down.
        for id in ids {
            let workout = try #require(store.workout(id: id))
            workout.volumeKg = 0
            workout.setsDone = 0
        }
        SeedState.row(in: store.context).workoutTotalsBackfilled = false
        try store.context.save()

        // Reads never write: unstamped rows fall back to their sets until the launch pass runs.
        #expect(store.lifetimeStats().volumeKg == 60 * 8 + 65 * 8 + 70 * 8)
        #expect(!SeedState.row(in: store.context).workoutTotalsBackfilled)
        store.backfillWorkoutTotalsIfNeeded()
        #expect(store.lifetimeStats().volumeKg == 60 * 8 + 65 * 8 + 70 * 8)
        #expect(store.history().map(\.volumeKg).sorted() == [480, 520, 560])
        #expect(SeedState.row(in: store.context).workoutTotalsBackfilled)
        for id in ids {
            #expect(try #require(store.workout(id: id)).hasStampedTotals)
        }
        // A restored workout is re-stamped too.
        let lastID = try #require(ids.last)
        let deleted = try #require(store.deleteWorkout(id: lastID))
        store.restoreWorkout(deleted)
        let restored = try #require(store.workout(id: lastID))
        #expect(restored.volumeKg == 70 * 8)
    }

    @Test("a stamp that disagrees with the rows (a partial CloudKit batch) is corrected on the remote pass")
    func remotePassRestampsWrongTotals() throws {
        let store = try fx.makeStore()
        let routineID = fx.makeRoutine(store, exerciseID: fx.makeBench(store).id)
        let id = try #require(fx.logSessions(store, routineID: routineID, count: 1).first)
        let workout = try #require(store.workout(id: id))
        // Non-zero but wrong: `hasStampedTotals` is true, so the one-shot backfill skips it.
        workout.volumeKg = 1
        workout.setsDone = 1
        try store.context.save()
        #expect(store.restampWorkoutTotalsAfterRemoteChange() == 1)
        #expect(workout.volumeKg == 60 * 8)
        // Nothing left to correct on a second pass.
        #expect(store.restampWorkoutTotalsAfterRemoteChange() == 0)
    }

    // MARK: - finish() reads the finished list once

    @Test("finish() issues the same number of queries after 1 and after 5 prior sessions")
    func finishQueryCountDoesNotScaleWithHistory() throws {
        var counts: [Int] = []
        for prior in [1, 5] {
            let store = try fx.makeStore()
            let routineID = fx.makeRoutine(store, exerciseID: fx.makeBench(store).id)
            fx.logSessions(store, routineID: routineID, count: prior)
            let session = store.startWorkout(routineID: routineID)
            session.exercises[0].sets[1].weightKg = 100
            session.exercises[0].sets[1].reps = 8
            session.exercises[0].sets[1].isDone = true
            counts.append(fx.queries(store) { _ = store.finish(session: session) })
        }
        #expect(counts[0] == counts[1], "finish() grew with history: \(counts)")
    }

    @Test("finish() compares against the previous session on the same routine and finds its PRs")
    func finishSummaryStillSeesPrevious() throws {
        let store = try fx.makeStore()
        let routineID = fx.makeRoutine(store, exerciseID: fx.makeBench(store).id)
        fx.logSessions(store, routineID: routineID, count: 2)
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 100
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        let summary = store.finish(session: session)
        #expect(summary.prs.count == 1)
        #expect(summary.previous?.volumeKg == 520)
        #expect(summary.e1rmChanges.first?.previous != nil)
        #expect(store.lifetimeStats().workouts == 3)
    }

    // MARK: - PR rebuild in memory

    @Test("rebuildPersonalRecords issues the same number of queries for 2 and for 6 workouts")
    func rebuildQueryCountDoesNotScale() throws {
        var counts: [Int] = []
        for workouts in [2, 6] {
            let store = try fx.makeStore()
            let bench = fx.makeBench(store)
            let routineID = fx.makeRoutine(store, exerciseID: bench.id)
            fx.logSessions(store, routineID: routineID, count: workouts)
            counts.append(fx.queries(store) { store.rebuildPersonalRecords() })
            #expect(store.bestE1RMRecord(exerciseID: bench.id)?.weightKg == 60 + Double(workouts - 1) * 5)
            #expect(store.personalRecords().first?.records.isEmpty == false)
        }
        // Exactly: the two cache tables to clear, the finished list and the weigh-ins. It was
        // a fetch plus a `fetchFirst` per PR kind per exercise per workout.
        #expect(counts == [4, 4], "rebuild issued \(counts) queries for 2 and 6 workouts")
    }

    @Test("a rebuild keeps one most-reps row per weight and one row for every other kind")
    func rebuildKeepsPerWeightRepRecords() throws {
        let store = try fx.makeStore()
        let bench = fx.makeBench(store)
        let routineID = fx.makeRoutine(store, exerciseID: bench.id)
        for (weight, reps) in [(60.0, 8), (80.0, 5), (60.0, 10)] {
            let session = store.startWorkout(routineID: routineID)
            session.exercises[0].sets[1].weightKg = weight
            session.exercises[0].sets[1].reps = reps
            session.exercises[0].sets[1].isDone = true
            _ = store.finish(session: session)
        }
        let before = store.fetch(FetchDescriptor<PersonalRecordModel>())
            .map { "\($0.kind)@\($0.weightKg)=\($0.reps)" }.sorted()
        store.rebuildPersonalRecords()
        let after = store.fetch(FetchDescriptor<PersonalRecordModel>())
            .map { "\($0.kind)@\($0.weightKg)=\($0.reps)" }.sorted()
        #expect(after == before)
        let repsAtWeight = after.filter { $0.hasPrefix(PRKind.maxRepsAtWeight.rawValue) }
        #expect(repsAtWeight.count == 2, "one row per weight: \(repsAtWeight)")
    }

    // MARK: - Siri
}
