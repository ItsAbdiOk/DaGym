import Foundation
import GymCore

/// Where `WorkoutStore` reads the lifter's units when a caller hasn't passed one — the fallback
/// path for a store-formatted line (`lastSessions`, the PR list, the review digest). The store
/// has no `Preferences` (it outlives and underlies the view tree), so the app hands one in:
/// `userDefaults()` reads the same keys `Preferences` writes, which is also what the watch's
/// `WatchPreferences` writes; a test hands in fixed closures and never touches
/// `UserDefaults.standard`.
struct StoreUnitProvider {
    var weightUnit: @MainActor () -> WeightUnit
    var distanceUnit: @MainActor () -> DistanceUnit

    /// `Preferences.weightUnit`/`.distanceUnit` straight from storage. A distance unit that was
    /// never chosen follows the weight unit (kg → km, lb → mi), as `Preferences` does.
    static func userDefaults(_ defaults: UserDefaults = .standard) -> StoreUnitProvider {
        // `UserDefaults` is thread-safe but not `Sendable`; the closures only ever run on the
        // main actor, so the reference is handed across explicitly.
        nonisolated(unsafe) let defaults = defaults
        return StoreUnitProvider(
            weightUnit: {
                let raw = defaults.string(forKey: Preferences.Key.weightUnit) ?? ""
                return WeightUnit(rawValue: raw) ?? .kg
            },
            distanceUnit: {
                let raw = defaults.string(forKey: Preferences.Key.distanceUnit) ?? ""
                let weightRaw = defaults.string(forKey: Preferences.Key.weightUnit) ?? ""
                return DistanceUnit(rawValue: raw)
                    ?? DistanceUnit.matching(WeightUnit(rawValue: weightRaw) ?? .kg)
            }
        )
    }

    /// Fixed units, for tests.
    static func fixed(weight: WeightUnit, distance: DistanceUnit? = nil) -> StoreUnitProvider {
        StoreUnitProvider(
            weightUnit: { weight }, distanceUnit: { distance ?? DistanceUnit.matching(weight) }
        )
    }
}

extension WorkoutStore {
    /// The weight unit the store formats in when a caller doesn't pass one.
    var preferredWeightUnit: WeightUnit { units.weightUnit() }

    /// The distance unit the store formats cardio in when a caller doesn't pass one.
    var preferredDistanceUnit: DistanceUnit { units.distanceUnit() }
}
