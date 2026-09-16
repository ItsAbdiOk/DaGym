import Foundation
import SwiftData
import Testing

@testable import DaGymWatch

// The one place a watch suite gets a `WatchStore` from: one in-memory container, the phone's
// own `WorkoutStore` over its main context, and a `WatchStore` with the HealthKit runtime off,
// throwaway preferences and a throwaway App Group suite for its snapshots — so nothing a test
// writes outlives it or reaches another test.

/// A `WatchStore` and everything it stands on. The container is kept on purpose: a
/// `ModelContext` only weakly references it, and a fetch on a context whose container has
/// been released traps inside SwiftData — end every test with `withExtendedLifetime(fixture) {}`.
@MainActor
struct WatchFixture {
    /// The store the "phone side" of a test writes with. Either `watch.store` itself or, with
    /// `separatePhone`, a second store over the same context — the shape a phone and a watch
    /// actually have, where neither sees the other's in-memory caches.
    let phone: WorkoutStore
    let watch: WatchStore
    let container: ModelContainer
    /// The App Group stand-in the watch writes its complication snapshot to.
    let snapshotSuite: UserDefaults
}

/// - Parameters:
///   - seeded: run `WatchSampleSeeder` first, so today has a routine and bench has history.
///   - separatePhone: give `phone` its own `WorkoutStore` rather than the watch's.
///   - haptics: the wrist preference; the default is what a fresh watch has.
///   - refreshHome: build Home once before returning, as the app does on launch.
///   - startsToday: start today's routine on the watch (implies `seeded`).
@MainActor
func makeWatchFixture(
    seeded: Bool = true, separatePhone: Bool = false, haptics: Bool = true,
    refreshHome: Bool = false, startsToday: Bool = false
) throws -> WatchFixture {
    let container = try ModelContainer.dagym(inMemory: true)
    let store = WorkoutStore(context: container.mainContext, photoContext: nil)
    let phone = separatePhone ? WorkoutStore(context: container.mainContext, photoContext: nil) : store
    if seeded || startsToday { WatchSampleSeeder.seed(store: phone) }
    let preferences = WatchPreferences(defaults: WatchTestDefaults.fresh())
    preferences.haptics = haptics
    let snapshotSuite = WatchTestDefaults.fresh()
    let watch = WatchStore(
        store: store, preferences: preferences, runtime: WatchWorkoutRuntime(isEnabled: false),
        snapshotSuite: snapshotSuite
    )
    if refreshHome { watch.refreshHome() }
    if startsToday {
        let routine = try #require(store.todaysRoutine())
        watch.start(routineID: routine.id)
    }
    return WatchFixture(phone: phone, watch: watch, container: container, snapshotSuite: snapshotSuite)
}

/// A throwaway `UserDefaults` suite per test, so preferences never leak between them.
enum WatchTestDefaults {
    static func fresh() -> UserDefaults {
        let name = "watch-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
