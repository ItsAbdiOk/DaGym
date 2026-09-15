import Foundation

/// The `Preferences.Key` names the shared `WorkoutStore` reads straight out of
/// `UserDefaults.standard` (`WorkoutStore+Equipment.preferredWeightUnit`,
/// `WorkoutStore+Cardio.preferredDistanceUnit`). The phone's `Preferences` type is UIKit-adjacent
/// (it drives `DGColor`), so the watch compiles this mirror instead. `WatchPreferences` writes
/// the same keys, so the store's rounding grids and unit-aware lines follow the watch's own
/// Units row. The strings must stay identical to `DaGym/Design/Preferences+Storage.swift`.
enum Preferences {
    enum Key {
        static let weightUnit = "weightUnit"
        static let distanceUnit = "distanceUnit"
        /// Read by `WatchPreferences.trainingCalendar`; the phone's default (`true`) is mirrored.
        static let weekStartsMonday = "weekStartsMonday"
    }
}
