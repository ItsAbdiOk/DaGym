import Foundation
import HealthKit
import Testing

@testable import DaGymWatch

/// `WatchWorkoutRuntime.start` awaits HealthKit's authorisation before it can open a session;
/// `end`/`discard` in that window used to find no session and return, and the session then
/// started behind a workout that no longer existed. The token is what closes the window.
@Suite("Watch runtime start token")
struct WatchRuntimeStartTokenTests {
    @Test("a start cancelled while awaiting authorisation is not current when the wait ends")
    func cancelledStartDoesNotProceed() {
        var token = WatchWorkoutRuntime.StartToken()
        let first = token.request()
        #expect(token.isPending)
        #expect(token.isCurrent(first))

        token.cancel() // `discard()` ran while the sheet was up.

        #expect(!token.isPending)
        #expect(!token.isCurrent(first))
    }

    @Test("a later start retires the earlier token, and a completed start clears it")
    func laterStartWins() {
        var token = WatchWorkoutRuntime.StartToken()
        let first = token.request()
        let second = token.request()
        #expect(!token.isCurrent(first))
        #expect(token.isCurrent(second))

        token.clear() // `begin` opened the session.
        #expect(!token.isPending)
        #expect(!token.isCurrent(second))
    }

    /// HealthKit can end a session underneath the app; holding a dead reference refused every
    /// later start for the rest of the launch. Our own `end()` reaches `.stopped` first and
    /// must save before the references go.
    @Test("stopped saves, ended releases, running and paused do nothing")
    func stateReactions() {
        #expect(WatchWorkoutRuntime.reaction(to: .stopped) == .save)
        #expect(WatchWorkoutRuntime.reaction(to: .ended) == .release)
        #expect(WatchWorkoutRuntime.reaction(to: .running) == WatchWorkoutRuntime.StateReaction.none)
        #expect(WatchWorkoutRuntime.reaction(to: .paused) == WatchWorkoutRuntime.StateReaction.none)
        #expect(WatchWorkoutRuntime.reaction(to: .notStarted) == WatchWorkoutRuntime.StateReaction.none)
    }

    @Test("the read set stays heart rate and active energy, share is the workout type only")
    @MainActor
    func authorisationSets() {
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        #expect(WatchWorkoutRuntime.readTypes == read)
        #expect(WatchWorkoutRuntime.shareTypes == [HKObjectType.workoutType()])
    }
}
