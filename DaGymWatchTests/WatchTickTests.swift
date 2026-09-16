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
    @Test("a fresh session does not tick until its first rest starts")
    func idleUntilRest() throws {
        let fixture = try makeWatchFixture(startsToday: true)
        let watch = fixture.watch
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
        withExtendedLifetime(fixture) {}
    }

    @Test("skipping the rest leaves nothing to tick, and the loop lets itself stop")
    func skipEndsNeed() async throws {
        let fixture = try makeWatchFixture(startsToday: true)
        let watch = fixture.watch
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
        withExtendedLifetime(fixture) {}
    }

    @Test("a timed hold needs the tick with no rest running")
    func holdNeedsTick() throws {
        let fixture = try makeWatchFixture(startsToday: true)
        let watch = fixture.watch
        let session = try #require(watch.session)
        let plank = try #require(session.exercises.first { $0.exercise.loggingStyle == .timedHold })
        #expect(!watch.needsTicker)

        watch.startHold(exerciseID: plank.id)

        #expect(session.timedHold != nil)
        #expect(watch.needsTicker)
        #expect(watch.isTicking)
        watch.discard()
        withExtendedLifetime(fixture) {}
    }
}
