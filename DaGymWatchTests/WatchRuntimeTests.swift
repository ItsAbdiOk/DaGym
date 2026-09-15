import Foundation
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
}
