import Foundation
import SwiftData

/// The `WorkoutStore` an App Intent that runs without a live UI (`openAppWhenRun = false`:
/// `LogBodyweightIntent`, `LastSessionIntent`, `GetStreakIntent`, `ExerciseEntityQuery`) reads
/// and writes. Siri can invoke them with the app fully backgrounded or not running, so nothing
/// guarantees a `RootView` to reach into — but the intent still runs in the app process, so it
/// shares `ContainerProvider`'s one container (and store) with the app instead of opening its
/// own. That honours `Preferences.iCloudSyncEnabled`, falls back to a local store the same way
/// the app does, and means a bodyweight logged through Siri lands in the context the open app is
/// reading from. `LaunchFlags.isTesting` short-circuits to `nil` so `AppIntentsTesting` and
/// unit-test hosts never touch a real on-disk/CloudKit container.
@MainActor
enum IntentStoreAccess {
    #if DEBUG
    /// What a unit test hands the intents instead of the live container: `perform()` is then
    /// exercised end to end against an in-memory store and an isolated `Preferences` suite.
    /// Debug-only so a shipped binary has no way to be pointed at a throwaway store.
    static var testOverride: (store: WorkoutStore, preferences: Preferences)?
    #endif

    static func makeStore() -> WorkoutStore? {
        #if DEBUG
        if let testOverride { return testOverride.store }
        #endif
        guard !LaunchFlags.isTesting else { return nil }
        let provider = ContainerProvider.shared
        let store = provider.store(cloudKitEnabled: Preferences().iCloudSyncEnabled)
        // A throwaway in-memory fallback must not accept writes: a bodyweight logged through
        // Siri into it would vanish with the process, silently.
        guard provider.mainResolution?.isDurable == true else { return nil }
        return store
    }

    /// The app's own preferences (`UserDefaults.standard`) — the unit, weekly goal and week
    /// start every spoken answer is phrased in — unless a test has overridden them.
    static func preferences() -> Preferences {
        #if DEBUG
        if let testOverride { return testOverride.preferences }
        #endif
        return Preferences()
    }
}
