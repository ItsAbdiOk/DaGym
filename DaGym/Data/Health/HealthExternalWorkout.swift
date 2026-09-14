import Foundation

/// One `HKWorkout` logged by another app (Watch, a third-party trainer app, etc.) that looks
/// like strength training. Never one of ours — `HealthKitStore.externalStrengthWorkouts` filters
/// out anything carrying our own `DaGymWorkoutID` metadata before it ever reaches this struct.
struct HealthExternalWorkout: Sendable, Equatable {
    /// `HKWorkout.uuid.uuidString` — the dedupe key. Stored on `ImportedHealthWorkoutModel` in
    /// the always-local Health store once imported (and tombstoned there if the user deletes it),
    /// so a later pull never imports the same sample twice or resurrects a deleted one.
    var uuid: String
    var start: Date
    var end: Date
    var title: String
}
