import Foundation
import GymCore

/// The spec's crown table: "Detents follow the exercise increment: 2.5 kg or 5 lb for barbells,
/// 2 kg dumbbells, 1 rep, 5 kg assistance, 15 s when scrubbing rest." One detent per
/// `CrownField`, in the display unit, plus the range the crown is clamped to.
enum CrownDetents {
    /// 15 s per detent on the full-screen rest.
    static let restSeconds = 15

    static func step(for field: CrownField, exercise: ExerciseInfo, unit: WeightUnit) -> Double {
        switch field {
        case .weight: SetFormat.weightStep(for: exercise, unit: unit)
        case .reps: 1
        case .effort: 0.5
        case .assistance: unit == .kg ? 5 : 10
        case .distance: 0.1
        }
    }

    static func range(for field: CrownField) -> ClosedRange<Double> {
        switch field {
        case .effort: 5...10
        case .reps: 0...100
        case .distance: 0...200
        case .weight, .assistance: 0...1000
        }
    }
}
