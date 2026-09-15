import GymCore
import SwiftUI

/// The crown side of an exercise page: focus, the crown's value in the display unit, and the
/// write back onto the session's `SetEntry`. Pulled out of `ExercisePage` so the page is the
/// layout and this is the arithmetic — and so the arithmetic is testable without a view.
enum ExerciseCrown {
    /// The crown position that shows `field`'s current value for `set`.
    @MainActor
    static func value(
        for field: CrownField, set: SetEntry, entry: WorkoutExerciseEntry, preferences: WatchPreferences
    ) -> Double {
        let unit = preferences.weightUnit
        switch field {
        case .weight: return unit.display(kg: set.weightKg)
        case .reps: return Double(entry.exercise.isPerSide ? set.reps / 2 : set.reps)
        case .effort: return set.effort?.rpe ?? 8
        case .assistance: return unit.display(kg: WorkoutStore.assistanceKg(set, style: .assisted) ?? 0)
        case .distance: return (set.cardioMeters ?? 0) / preferences.distanceUnit.meters
        }
    }

    /// Writes a crown position back onto the on-deck set of `entry`.
    @MainActor
    static func write(
        field: CrownField, value: Double, entry: WorkoutExerciseEntry,
        preferences: WatchPreferences, store: WatchStore
    ) {
        let unit = preferences.weightUnit
        store.updateSet(exerciseID: entry.id) { set in
            switch field {
            case .weight: set.weightKg = unit.toKg(value)
            case .reps: set.reps = Int(value.rounded()) * (entry.exercise.isPerSide ? 2 : 1)
            case .effort: set.effort = Effort(rpe: value)
            case .assistance: set.weightKg = unit.toKg(value)
            case .distance:
                let meters = value * preferences.distanceUnit.meters
                if set.isDone { set.distanceMeters = meters } else { set.targetDistanceMeters = meters }
            }
        }
    }

    /// One detent either way from `current`, clamped to the field's range — VoiceOver's
    /// swipe up / down on a stepper.
    static func adjusted(
        _ current: Double, field: CrownField, direction: AccessibilityAdjustmentDirection,
        exercise: ExerciseInfo, unit: WeightUnit
    ) -> Double {
        let step = CrownDetents.step(for: field, exercise: exercise, unit: unit)
        let range = CrownDetents.range(for: field)
        let next = direction == .increment ? current + step : current - step
        return min(range.upperBound, max(range.lowerBound, next))
    }
}

/// Binds the crown to the focused field of an exercise page: the rotation's detent and range
/// follow `focus`, every crown change is written to the session, and a new on-deck set drops
/// focus so the crown never edits a row the lifter has moved past.
struct ExerciseCrownModifier: ViewModifier {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences
    var entry: WorkoutExerciseEntry
    var currentSetID: UUID?
    @Binding var focus: CrownField?
    @Binding var crown: Double

    func body(content: Content) -> some View {
        content
            .modifier(CrownBinding(crown: $crown, focus: focus, step: step, range: range))
            .onChange(of: crown) { _, value in
                guard let focus else { return }
                ExerciseCrown.write(
                    field: focus, value: value, entry: entry, preferences: preferences, store: store
                )
            }
            .onChange(of: currentSetID) { _, _ in focus = nil }
    }

    private var step: Double {
        CrownDetents.step(for: focus ?? .reps, exercise: entry.exercise, unit: preferences.weightUnit)
    }

    private var range: ClosedRange<Double> { CrownDetents.range(for: focus ?? .reps) }
}
