import Foundation
import GymCore

/// Which of the spec's set layouts a row takes (2A–2G plus cardio), decided from the exercise's
/// logging style first and the set's kind second.
enum SetShape {
    case standard, warmup, amrap, bodyweight, assisted, timedHold, cardio, perSide

    static func shape(for entry: WorkoutExerciseEntry, set: SetEntry) -> SetShape {
        switch entry.exercise.loggingStyle {
        case .timedHold: return .timedHold
        case .cardio: return .cardio
        case .assisted: return set.kind == .warmup ? .warmup : .assisted
        case .bodyweightReps: return set.weightKg > 0 ? .standard : .bodyweight
        case .weightReps, .weightedBodyweight: break
        }
        if set.kind == .warmup { return .warmup }
        if set.kind == .amrap { return .amrap }
        if entry.exercise.isPerSide { return .perSide }
        return .standard
    }
}

/// Formatting shared by the set layouts, the rest views and the always-on screens.
enum SetFormat {
    /// "100" / "22.5" in the lifter's unit, no symbol.
    static func weight(_ kg: Double, unit: WeightUnit) -> String {
        unit.format(kg: kg)
    }

    /// "100 × 5" — the rest views' "Logged" / "Next" line.
    static func weightByReps(_ kg: Double, reps: Int, unit: WeightUnit) -> String {
        "\(unit.format(kg: kg)) × \(reps)"
    }

    /// "100 kg × 5".
    static func weightUnitByReps(_ kg: Double, reps: Int, unit: WeightUnit) -> String {
        "\(unit.format(kg: kg)) \(unit.symbol) × \(reps)"
    }

    /// One crown detent for a weight card, in the display unit: the exercise's own increment
    /// in kg, 5 lb (2.5 lb for dumbbells under 2 kg) in lb.
    static func weightStep(for exercise: ExerciseInfo, unit: WeightUnit) -> Double {
        switch unit {
        case .kg: return max(exercise.incrementKg, 0.5)
        case .lb: return exercise.incrementKg < 2 ? 2.5 : 5
        }
    }

    /// The position of this set among the exercise's counting sets ("Set 2 of 4"), or among its
    /// warm-ups for a warm-up row ("Warm-up 2 of 2").
    static func position(of set: SetEntry, in entry: WorkoutExerciseEntry) -> (index: Int, count: Int) {
        let peers = entry.sets.filter { ($0.kind == .warmup) == (set.kind == .warmup) }
        let index = (peers.firstIndex { $0.id == set.id } ?? 0) + 1
        return (index, peers.count)
    }

    static func e1RM(_ kg: Double, reps: Int) -> Double? {
        OneRepMax.isEligible(weight: kg, reps: reps) ? OneRepMax.estimate(weight: kg, reps: reps) : nil
    }
}
