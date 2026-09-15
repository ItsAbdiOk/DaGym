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

/// Turns crown movement on the full-screen rest into whole 15 s steps *relative to where the
/// crown was*, not to where the countdown is. The crown position is a dial the lifter turns
/// while the remaining time keeps falling underneath it, so reading it as an absolute target
/// drifted: 90 s on the dial, 75 s left after a wait, one detent up asked for 105 — thirty
/// seconds, not fifteen — and one detent down *added* time.
struct CrownRestScrubber {
    private var last: Double
    private var pending: Double = 0

    init(position: Double) {
        last = position
    }

    /// Seconds to add (negative to take away) for the crown reaching `position`: a multiple of
    /// `CrownDetents.restSeconds`, 0 until a whole detent has accumulated. Fractions carry over,
    /// so a slow turn still lands on the same steps as a flick.
    mutating func turned(to position: Double) -> Int {
        pending += position - last
        last = position
        let detent = Double(CrownDetents.restSeconds)
        let steps = (pending / detent).rounded(.towardZero)
        guard steps != 0 else { return 0 }
        pending -= steps * detent
        return Int(steps) * CrownDetents.restSeconds
    }
}
