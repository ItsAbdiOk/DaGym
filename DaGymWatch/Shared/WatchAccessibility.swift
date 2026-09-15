import Foundation
import GymCore

/// The spec's VoiceOver strings, built here so they can be tested without rendering:
/// "Weight, 100 kilograms, adjustable" (the trait supplies "adjustable"), the set row as one
/// element — "Set 2 of 4, 100 kilograms by 5 reps" — the dots as "2 of 4 sets done", and the
/// rest timer's two announcements, at 30 seconds and zero.
enum WatchAccessibility {
    /// "100 kilograms" / "225 pounds" — the spoken form of a weight in the lifter's unit.
    static func spokenWeight(kg: Double, unit: WeightUnit) -> String {
        "\(unit.format(kg: kg)) \(unitWord(unit))"
    }

    static func unitWord(_ unit: WeightUnit) -> String {
        switch unit {
        case .kg: "kilograms"
        case .lb: "pounds"
        }
    }

    /// The value a stepper card speaks: "100 kilograms", "5 reps", "20 kilograms assistance".
    static func stepperValue(
        field: CrownField, value: Double, unit: WeightUnit, perSide: Bool = false
    ) -> String {
        switch field {
        case .weight: spokenWeight(kg: value, unit: unit)
        case .assistance: "\(spokenWeight(kg: value, unit: unit)) assistance"
        case .reps: "\(Int(value)) reps" + (perSide ? " per side" : "")
        case .effort: "RPE \(Effort(rpe: value).displayValue(scale: .rpe))"
        case .distance: DistanceUnit.matching(unit).formatWithSymbol(meters: value)
        }
    }

    /// "Set 2 of 4, 100 kilograms by 5 reps" — the row before its children. Warm-ups name
    /// themselves; bodyweight and timed rows drop the weight.
    static func setRow(
        shape: SetShape, position: (index: Int, count: Int), weightKg: Double, reps: Int,
        targetSeconds: Int? = nil, unit: WeightUnit
    ) -> String {
        let head = shape == .warmup
            ? "Warm-up \(position.index) of \(position.count)"
            : "Set \(position.index) of \(position.count)"
        switch shape {
        case .bodyweight: return "\(head), \(reps) reps"
        case .timedHold, .cardio:
            guard let targetSeconds else { return head }
            return "\(head), target \(CardioPace.clock(targetSeconds))"
        case .assisted:
            return "\(head), \(spokenWeight(kg: weightKg, unit: unit)) assistance by \(reps) reps"
        case .perSide:
            return "\(head), \(spokenWeight(kg: weightKg, unit: unit)) by \(reps / 2) reps per side"
        case .standard, .warmup, .amrap:
            return "\(head), \(spokenWeight(kg: weightKg, unit: unit)) by \(reps) reps"
        }
    }

    static func dots(done: Int, total: Int) -> String { "\(done) of \(total) sets done" }

    /// What the rest timer announces for a remaining second — only at 30 and 0, never every
    /// second.
    static func restAnnouncement(remaining: Int) -> String? {
        switch remaining {
        case 30: "30 seconds of rest left"
        case 0: "Rest over"
        default: nil
        }
    }
}
