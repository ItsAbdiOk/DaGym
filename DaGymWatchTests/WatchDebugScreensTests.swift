import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// `-dgWatchScreen summary` must finish a real session: the screenshot shows the sets it logged
/// and a plausible clock, not "Sets 1 · Time 0:00".
@MainActor
@Suite("Watch debug screens")
struct WatchDebugScreensTests {
    @Test("the summary route finishes Push A with its four working sets and an elapsed time")
    func summaryRouteFinishesARealSession() throws {
        let fixture = try makeWatchFixture(separatePhone: true, refreshHome: true)
        let watch = fixture.watch
        WatchDebugScreens.apply("summary", store: watch, isSample: true)
        let summary = try #require(watch.summary)
        #expect(watch.session == nil)
        #expect(summary.setsDone == 4)
        #expect(summary.volumeKg > 1_500)
        #expect(summary.durationSeconds >= 30 * 60)
        withExtendedLifetime(fixture) {}
    }
}
