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
    private func makeWatch() throws -> (WatchStore, ModelContainer) {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: container.mainContext, photoContext: nil)
        WatchSampleSeeder.seed(store: store)
        let watch = WatchStore(
            store: store, preferences: WatchPreferences(defaults: WatchTestDefaults.fresh()),
            runtime: WatchWorkoutRuntime(isEnabled: false)
        )
        let routine = try #require(store.todaysRoutine())
        watch.start(routineID: routine.id)
        return (watch, container)
    }

    @Test("swiping to another page cancels the pending repeat")
    func pageChangeAcknowledges() throws {
        let (watch, container) = try makeWatch()
        let session = try #require(watch.session)
        session.onRestTick?(0)
        #expect(watch.isRestEndRepeatPending)

        watch.pageIndex += 1

        #expect(!watch.isRestEndRepeatPending)
        withExtendedLifetime(container) {}
    }
}
