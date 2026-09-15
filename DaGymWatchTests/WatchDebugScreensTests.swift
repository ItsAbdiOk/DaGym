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
    private func makeWatch() throws -> (WatchStore, ModelContainer) {
        let container = try ModelContainer.dagym(inMemory: true)
        let phone = WorkoutStore(context: container.mainContext, photoContext: nil)
        WatchSampleSeeder.seed(store: phone)
        let watch = WatchStore(
            store: WorkoutStore(context: container.mainContext, photoContext: nil),
            preferences: WatchPreferences(defaults: WatchTestDefaults.fresh()),
            runtime: WatchWorkoutRuntime(isEnabled: false)
        )
        watch.refreshHome()
        return (watch, container)
    }

    @Test("the summary route finishes Push A with its four working sets and an elapsed time")
    func summaryRouteFinishesARealSession() throws {
        let (watch, container) = try makeWatch()
        WatchDebugScreens.apply("summary", store: watch, isSample: true)
        let summary = try #require(watch.summary)
        #expect(watch.session == nil)
        #expect(summary.setsDone == 4)
        #expect(summary.volumeKg > 1_500)
        #expect(summary.durationSeconds >= 30 * 60)
        withExtendedLifetime(container) {}
    }
}
