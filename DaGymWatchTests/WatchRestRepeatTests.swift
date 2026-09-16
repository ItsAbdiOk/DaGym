import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// Rest-zero success is "repeated once after five seconds if unacknowledged". Logging, stopping
/// a hold or swiping to another page all acknowledge it — not only starting the next rest.
@MainActor
@Suite("Watch rest-end repeat")
struct WatchRestRepeatTests {
    @Test("swiping to another page cancels the pending repeat")
    func pageChangeAcknowledges() throws {
        let fixture = try makeWatchFixture(startsToday: true)
        let watch = fixture.watch
        let session = try #require(watch.session)
        session.onRestTick?(0)
        #expect(watch.isRestEndRepeatPending)

        watch.pageIndex += 1

        #expect(!watch.isRestEndRepeatPending)
        withExtendedLifetime(fixture) {}
    }
}
