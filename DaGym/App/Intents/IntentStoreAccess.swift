import Foundation
import SwiftData

/// Opens a short-lived `WorkoutStore` for an App Intent that runs outside a live app process
/// (`openAppWhenRun = false`: `LogBodyweightIntent`, `LastSessionIntent`, `ExerciseEntityQuery`).
/// None of those are guaranteed a running `WorkoutStore` to reach into — Siri can invoke them
/// with the app fully backgrounded or not running — so each opens (and quickly discards) its own
/// container instead. `LaunchFlags.isTesting` short-circuits to `nil` so `AppIntentsTesting` and
/// unit-test hosts never touch a real on-disk/CloudKit container.
@MainActor
enum IntentStoreAccess {
    static func makeStore() -> WorkoutStore? {
        guard !LaunchFlags.isTesting else { return nil }
        guard let container = try? ModelContainer.dagym() else { return nil }
        return WorkoutStore(context: ModelContext(container))
    }
}
