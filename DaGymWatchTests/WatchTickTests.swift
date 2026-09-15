import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// The 1 Hz loop runs only while something on the session moves by the second — a rest or a
/// timed hold. With the HealthKit session keeping the app alive, a tick for the whole workout
/// was a wake-up per second, wrist down, for an hour of mostly nothing.
@MainActor
@Suite("Watch ticker gating")
struct WatchTickTests {
    private func makeWatch() throws -> (WatchStore, ModelContainer) {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: container.mainContext, photoContext: nil)
        WatchSampleSeeder.seed(store: store)
        let watch = WatchStore(
            store: store, preferences: WatchPreferences(defaults: WatchTestDefaults.fresh()),
            runtime: WatchWorkoutRuntime(isEnabled: false), snapshotSuite: WatchTestDefaults.fresh()
        )
        let routine = try #require(store.todaysRoutine())
        watch.start(routineID: routine.id)
        return (watch, container)
    }

    @Test("a fresh session does not tick until its first rest starts")
    func idleUntilRest() throws {
        let (watch, container) = try makeWatch()
        let session = try #require(watch.session)
        #expect(!watch.needsTicker)
        #expect(!watch.isTicking)

        let bench = try #require(session.exercises.first)
        watch.logCurrentSet(exerciseID: bench.id)

        #expect(session.isResting)
        #expect(watch.needsTicker)
        #expect(watch.isTicking)
        watch.discard()
        #expect(!watch.isTicking)
        withExtendedLifetime(container) {}
    }

    @Test("skipping the rest leaves nothing to tick, and the loop lets itself stop")
    func skipEndsNeed() async throws {
        let (watch, container) = try makeWatch()
        let session = try #require(watch.session)
        let bench = try #require(session.exercises.first)
        watch.logCurrentSet(exerciseID: bench.id)
        #expect(watch.isTicking)

        watch.skipRest()
        #expect(!watch.needsTicker)
        // The loop checks `needsTicker` after its next one-second sleep and exits.
        try await Task.sleep(for: .milliseconds(1500))
        #expect(!watch.isTicking)

        // The next rest starts it again.
        watch.logCurrentSet(exerciseID: bench.id)
        #expect(watch.isTicking)
        watch.discard()
        withExtendedLifetime(container) {}
    }

    @Test("a timed hold needs the tick with no rest running")
    func holdNeedsTick() throws {
        let (watch, container) = try makeWatch()
        let session = try #require(watch.session)
        let plank = try #require(session.exercises.first { $0.exercise.loggingStyle == .timedHold })
        #expect(!watch.needsTicker)

        watch.startHold(exerciseID: plank.id)

        #expect(session.timedHold != nil)
        #expect(watch.needsTicker)
        #expect(watch.isTicking)
        watch.discard()
        withExtendedLifetime(container) {}
    }
}
