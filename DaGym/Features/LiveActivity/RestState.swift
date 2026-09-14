import Foundation
import GymCore

/// Everything `WorkoutSession` knows about a rest-state change, handed to
/// `RestActivityController` through `WorkoutSession.onRestStateChange`. This type (unlike
/// `RestActivityAttributes`) references app-only concepts, so it stays out of the widget target.
/// Its own file so the watch app (which has no ActivityKit) compiles it alongside `WorkoutSession`.
struct RestState {
    var remaining: Int
    var total: Int
    /// The wall-clock moment the rest ends — the same instant the in-app pill counts to.
    var endDate: Date
    var workoutTitle: String
    var exerciseName: String
    var setNumber: Int
    var setCount: Int
    var nextWeightKg: Double?
    var nextReps: Int?
    var fallbackNextLabel: String
    var isEnded: Bool
    var isSkipped: Bool
    /// The on-deck exercise's routine glyph — see `RestActivityAttributes.routineSymbolName`.
    var routineSymbolName: String = "dumbbell"
    var routineTint: String = "coral"

    /// "82.5 kg × 8" / "180 lb × 8" when the next step is a plain weight × reps set, else the
    /// session's own fallback text ("Next Bench Press" / "Last set done").
    func nextSetLabel(unit: WeightUnit) -> String {
        guard let nextWeightKg, let nextReps else { return fallbackNextLabel }
        return "\(unit.format(kg: nextWeightKg)) \(unit.symbol) × \(nextReps)"
    }

    var setLabel: String { "Set \(setNumber) of \(setCount)" }
}
