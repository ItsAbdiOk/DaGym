import CoreData
import Foundation
import SwiftData
import Testing

@testable import DaGym

/// Pins the fix for the per-tombstone N+1 in `ExerciseSeeder.dedupe`. A device whose iCloud
/// import double-seeded keeps one tombstone per seeded exercise for 30 days, and the pass runs
/// twice at launch and once after every CloudKit transaction. Each settled tombstone used to
/// cost three predicate fetches and two relationship faults, so the owner's phone spent ~3 s
/// on the main thread per pass — measured with Time Profiler as the "freezes while scrolling
/// during a sync" report. No wall-clock assertions; the query count is what must stay flat.
@MainActor
@Suite("Seed dedupe query counts")
struct SeedDedupePerformanceTests {
    /// A settled pass, exactly: the exercise list, the three bare-id tables (PR cache, PR
    /// events, notes) and the two relationship tables (routine slots, workout entries) pointing
    /// at tombstones. The old shape added five per tombstone on top.
    private static let settledPassQueries = 6
    /// A store with nothing to fold costs one query (the exercise list) — and the pass runs
    /// after every remote change, so it must stay at one.
    private static let cleanStoreQueries = 1

    /// Tombstones `count` seeded exercises the way an iCloud double-seed does: a second copy
    /// under a new id, folded once so the loser is already settled.
    private func settleTombstones(count: Int, in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<ExerciseModel>())
        for model in existing.prefix(count) {
            let copy = ExerciseModel(
                seedID: model.seedID, name: model.name, primaryMuscles: model.primaryMuscles,
                equipment: model.equipment, loggingStyle: model.loggingStyle,
                createdAt: model.createdAt.addingTimeInterval(60)
            )
            context.insert(copy)
        }
        try context.save()
        #expect(ExerciseSeeder.dedupe(in: context) == count)
        try context.save()
    }

    private func queriesForSettledPass(tombstones: Int) throws -> Int {
        let context = try makeContext(seed: .exercises)
        try settleTombstones(count: tombstones, in: context)
        let before = ExerciseSeeder.dedupeQueryCount
        #expect(ExerciseSeeder.dedupe(in: context) == 0)
        return ExerciseSeeder.dedupeQueryCount - before
    }

    @Test("a settled pass issues the same number of queries for 2 and for 12 tombstones")
    func settledPassQueryCountDoesNotScale() throws {
        let small = try queriesForSettledPass(tombstones: 2)
        let big = try queriesForSettledPass(tombstones: 12)
        #expect(small == big, "dedupe query count grew with tombstones — \(small) for 2, \(big) for 12")
        #expect(
            big == Self.settledPassQueries,
            "a settled dedupe pass issued \(big) queries for 12 tombstones, budget \(Self.settledPassQueries)"
        )
    }

    /// The two relationship prefetches filter on an optional through a relationship keypath.
    /// This project has twice seen an optional UUID compared against nil come back *empty*
    /// (`WorkoutStore.liveExercises`, `BackupService.liveExercises`), and an empty prefetch
    /// here would mean late CloudKit children of a tombstone were never re-pointed and the
    /// 30-day sweep then detached them. Pins that the fetch returns exactly the tombstone's
    /// children — not none, and not the live rows' as well.
    @Test("the tombstone-child prefetch returns exactly the rows pointing at tombstones")
    func tombstoneChildPrefetchIsExact() throws {
        let context = try makeContext(seed: .exercises)
        try settleTombstones(count: 3, in: context)
        let all = try context.fetch(FetchDescriptor<ExerciseModel>())
        let tombstone = try #require(all.first { $0.isMergedAway })
        let live = try #require(all.first { !$0.isMergedAway })
        let workout = WorkoutModel(title: "Push A", endedAt: Date())
        context.insert(workout)
        context.insert(WorkoutExerciseModel(order: 0, exercise: tombstone, workout: workout))
        context.insert(WorkoutExerciseModel(order: 1, exercise: live, workout: workout))
        let routine = RoutineModel(name: "Push A")
        context.insert(routine)
        context.insert(RoutineExerciseModel(order: 0, exercise: tombstone, routine: routine))
        context.insert(RoutineExerciseModel(order: 1, exercise: live, routine: routine))
        try context.save()

        let children = ExerciseSeeder.FoldChildren(context: context)
        #expect(children.entries(of: tombstone).count == 1, "tombstone entry prefetch came back wrong")
        #expect(children.slots(of: tombstone).count == 1, "tombstone slot prefetch came back wrong")
        #expect(children.entries(of: live).count == 1)
        #expect(children.slots(of: live).count == 1)
    }

    @Test("a clean store costs one query — the pass runs after every remote change")
    func cleanStoreIsOneQuery() throws {
        let context = try makeContext(seed: .exercises)
        let before = ExerciseSeeder.dedupeQueryCount
        #expect(ExerciseSeeder.dedupe(in: context) == 0)
        #expect(ExerciseSeeder.dedupeQueryCount - before == Self.cleanStoreQueries)
    }

    @Test("a settled pass leaves nothing to save")
    func settledPassDoesNotDirtyTheContext() throws {
        let context = try makeContext(seed: .exercises)
        try settleTombstones(count: 5, in: context)
        #expect(!context.hasChanges)
        #expect(ExerciseSeeder.dedupe(in: context) == 0)
        #expect(!context.hasChanges, "a no-op pass re-wrote settled tombstones")
    }

    /// The store is held so the deduper's weak reference stays alive for the test's duration.
    @MainActor
    private struct DeduperHarness {
        let store: WorkoutStore
        let center = NotificationCenter()
        let deduper: RemoteChangeDeduper

        init(context: ModelContext, quiet: Duration, maxDelay: Duration) {
            store = WorkoutStore(context: context)
            deduper = store.startRemoteChangeDedupe(center: center, quietPeriod: quiet, maxDelay: maxDelay)
        }

        func postRemoteChange() { center.post(name: .NSPersistentStoreRemoteChange, object: nil) }
    }

    /// CloudKit posts one remote change per mirroring transaction; a sync is dozens in a row.
    @Test("a burst of remote changes runs one dedupe pass, after the burst goes quiet")
    func remoteChangeBurstIsOnePass() async throws {
        let harness = DeduperHarness(
            context: try makeContext(seed: .exercises), quiet: .milliseconds(80), maxDelay: .seconds(5)
        )
        for _ in 0..<10 {
            harness.postRemoteChange()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(harness.deduper.passCount == 0, "a pass ran while changes were still arriving")
        try await Task.sleep(for: .milliseconds(300))
        #expect(harness.deduper.passCount == 1)
    }

    @Test("a stream of remote changes that never goes quiet still gets a pass by maxDelay")
    func continuousRemoteChangesStillFold() async throws {
        let harness = DeduperHarness(
            context: try makeContext(seed: .exercises), quiet: .milliseconds(100),
            maxDelay: .milliseconds(150)
        )
        for _ in 0..<20 {
            harness.postRemoteChange()
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(
            harness.deduper.passCount >= 1,
            "no pass ran in 500 ms of continuous changes with a 150 ms ceiling"
        )
    }
}
