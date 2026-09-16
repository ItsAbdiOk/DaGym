import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// The complication snapshot is built from the store once and cached; every rest change only
/// splices `rest` into that cache. Rebuilding on each of them walked the whole history and
/// every routine on the main thread inside "Log set".
@MainActor
@Suite("Watch snapshot writer")
struct WatchSnapshotWriterTests {
    /// The most `logCurrentSet` may read from the store: `sync(session:)` alone. The
    /// finished-workout fetch (1) and the routine walk (2+) the old rebuild did per set are gone,
    /// and the snapshot path adds none.
    private static let logSetQueryCeiling = 4

    @Test("refreshHome builds the idle snapshot from the same fetches and writes it once")
    func refreshHomeWritesIdle() throws {
        let fixture = try makeWatchFixture()
        let (watch, suite) = (fixture.watch, fixture.snapshotSuite)

        watch.refreshHome()

        let written = WatchSnapshotStore.read(from: suite)
        #expect(written.rest == nil)
        #expect(written.streakWeeks == watch.home.streakWeeks)
        #expect(written.nextRoutineName == watch.home.todaysRoutine?.name)
        #expect(watch.snapshots.idle == written)
        #expect(watch.snapshots.reloadCount == 1)
        withExtendedLifetime(fixture) {}
    }

    @Test("a rest change splices into the cache without touching the store")
    func restSpliceDoesNotFetch() throws {
        let fixture = try makeWatchFixture()
        let (watch, suite) = (fixture.watch, fixture.snapshotSuite)
        watch.refreshHome()
        let idle = watch.snapshots.idle
        // Whole seconds: the App Group round-trips dates through JSON.
        let end = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 90).rounded())
        let rest = WatchSnapshot.Rest(
            endDate: end, totalSeconds: 90, nextLabel: "100 kg × 5", workoutTitle: "Push A"
        )
        let queries = watch.store.queryCount

        watch.snapshots.refresh(rest: rest)

        // Zero store reads on the rest path: the streak, week and next session come from the cache.
        #expect(watch.store.queryCount == queries)
        let written = WatchSnapshotStore.read(from: suite)
        #expect(written.rest == rest)
        #expect(written.streakWeeks == idle?.streakWeeks)
        #expect(written.nextRoutineName == idle?.nextRoutineName)
        withExtendedLifetime(fixture) {}
    }

    @Test("a rest that ran to its end is written without a timeline reload; an early skip reloads")
    func restEndReloadThrottle() throws {
        let fixture = try makeWatchFixture()
        let watch = fixture.watch
        watch.refreshHome()
        let start = watch.snapshots.reloadCount
        let now = Date()
        let rest = WatchSnapshot.Rest(
            endDate: now.addingTimeInterval(60), totalSeconds: 60, nextLabel: "next", workoutTitle: "t"
        )

        watch.snapshots.refresh(rest: rest, now: now)
        #expect(watch.snapshots.reloadCount == start + 1)
        // Ran out: the provider's timeline already hands back to idle at `endDate`.
        watch.snapshots.refresh(rest: nil, now: now.addingTimeInterval(60))
        #expect(watch.snapshots.reloadCount == start + 1)

        watch.snapshots.refresh(rest: rest, now: now)
        #expect(watch.snapshots.reloadCount == start + 2)
        // Skipped with 40 s left: the face would count down to nothing without a reload.
        watch.snapshots.refresh(rest: nil, now: now.addingTimeInterval(20))
        #expect(watch.snapshots.reloadCount == start + 3)
        withExtendedLifetime(fixture) {}
    }

    @Test("shouldReload keeps the natural rest end and every other change")
    func shouldReload() {
        let now = Date()
        let rest = WatchSnapshot.Rest(
            endDate: now.addingTimeInterval(30), totalSeconds: 30, nextLabel: "n", workoutTitle: "t"
        )
        #expect(WatchSnapshotWriter.shouldReload(from: nil, to: rest, now: now))
        #expect(WatchSnapshotWriter.shouldReload(from: nil, to: nil, now: now))
        #expect(WatchSnapshotWriter.shouldReload(from: rest, to: rest, now: now))
        #expect(WatchSnapshotWriter.shouldReload(from: rest, to: nil, now: now))
        #expect(!WatchSnapshotWriter.shouldReload(from: rest, to: nil, now: now.addingTimeInterval(29)))
        #expect(!WatchSnapshotWriter.shouldReload(from: rest, to: nil, now: now.addingTimeInterval(31)))
    }

    @Test("logging a set on a real session reaches the App Group as a rest with no history fetch")
    func logSetWritesRest() throws {
        let fixture = try makeWatchFixture()
        let (watch, suite) = (fixture.watch, fixture.snapshotSuite)
        watch.refreshHome()
        let routine = try #require(watch.store.todaysRoutine())
        watch.start(routineID: routine.id)
        let session = try #require(watch.session)
        let bench = try #require(session.exercises.first)
        // One idle rebuild per refreshHome; the sync inside logCurrentSet is the only store
        // work a logged set may do — the snapshot path adds none. Measured as a delta so the
        // shared store's own query count can change without touching this.
        let before = watch.store.queryCount
        watch.logCurrentSet(exerciseID: bench.id)
        let syncQueries = watch.store.queryCount - before

        #expect(session.isResting)
        #expect(WatchSnapshotStore.read(from: suite).rest != nil)
        #expect(
            syncQueries <= Self.logSetQueryCeiling,
            "logging a set read the store \(syncQueries) times, ceiling \(Self.logSetQueryCeiling)"
        )
        watch.discard()
        withExtendedLifetime(fixture) {}
    }

    @Test("the store's own post-finish refresh rebuilds this watch's cache, not a fresh one")
    func storeRefreshFindsWriter() throws {
        let fixture = try makeWatchFixture()
        let (watch, suite) = (fixture.watch, fixture.snapshotSuite)
        watch.refreshHome()
        let before = try #require(watch.snapshots.idle)

        // What `WorkoutStore.finish` / `saveRoutine` call.
        WidgetSnapshotWriter.refresh(store: watch.store)

        #expect(WatchSnapshotWriter.writer(for: watch.store) === watch.snapshots)
        #expect(watch.snapshots.idle == before)
        #expect(WatchSnapshotStore.read(from: suite) == before)
        withExtendedLifetime(fixture) {}
    }

    @Test("finishedWorkoutStartDates matches the models' dates, newest first")
    func startDates() throws {
        let fixture = try makeWatchFixture()
        let watch = fixture.watch
        let expected = watch.store.finishedWorkoutModelsNewestFirst().map(\.startedAt)
        #expect(!expected.isEmpty)
        #expect(watch.store.finishedWorkoutStartDates() == expected)
        withExtendedLifetime(fixture) {}
    }
}
