import CoreData
import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGymWatch

/// Routines, the schedule and history reach the watch by CloudKit import; Home must notice
/// without a relaunch, and without rebuilding per mirroring transaction.
@MainActor
@Suite("Watch remote-change observer")
struct WatchRemoteChangeTests {
    @Test("a burst of remote changes runs one debounced pass, and an idle Home is refreshed")
    func debouncedRefresh() async throws {
        let fixture = try makeWatchFixture(seeded: false)
        let (watch, store) = (fixture.watch, fixture.phone)
        let center = NotificationCenter()
        watch.observeRemoteChanges(center: center, quietPeriod: .milliseconds(50), maxDelay: .seconds(5))
        watch.refreshHome()
        #expect(watch.home.routines.isEmpty)

        // The "phone" seeds while the watch is listening — as an import landing would.
        WatchSampleSeeder.seed(store: store)
        for _ in 0..<5 { center.post(name: .NSPersistentStoreRemoteChange, object: nil) }
        try await Task.sleep(for: .milliseconds(300))

        let observer = try #require(watch.remoteChanges)
        #expect(observer.passCount == 1)
        #expect(!watch.home.routines.isEmpty)
        withExtendedLifetime(fixture) {}
    }

    @Test("a live session is left alone: the pass does not rebuild Home under a workout")
    func skipsWhileLive() async throws {
        let fixture = try makeWatchFixture(startsToday: true)
        let (watch, store) = (fixture.watch, fixture.phone)
        let center = NotificationCenter()
        watch.observeRemoteChanges(center: center, quietPeriod: .milliseconds(50), maxDelay: .seconds(5))
        let queries = store.queryCount

        center.post(name: .NSPersistentStoreRemoteChange, object: nil)
        try await Task.sleep(for: .milliseconds(300))

        #expect(watch.remoteChanges?.passCount == 1)
        #expect(store.queryCount == queries)
        watch.discard()
        withExtendedLifetime(fixture) {}
    }
}
