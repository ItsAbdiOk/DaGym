import ActivityKit
import Foundation

/// Shared Live Activity contract between the app (which starts/updates/ends the activity from
/// `RestActivityController`) and the `DaGymWidgets` extension (which renders it). Compiled into
/// both targets — see `project.yml`'s `DaGymWidgets.sources`. Keep this file free of any type
/// that only exists in the app target (e.g. `WorkoutSession`): the widget extension can't see it.
struct RestActivityAttributes: ActivityAttributes {
    /// Rendered as the lock screen ticking countdown and the ring; recomputed each update rather
    /// than ticked locally, so no timer runs inside the widget process.
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var totalSeconds: Int
        /// "82.5 × 8", or a fallback like "Last set done" when there's no next weight × reps.
        var nextSetLabel: String
        /// "Set 3 of 5".
        var setLabel: String

        var startDate: Date { endDate.addingTimeInterval(-Double(totalSeconds)) }
    }

    var workoutTitle: String
    var exerciseName: String
}
