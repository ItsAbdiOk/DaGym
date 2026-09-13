import Foundation

/// Estimated one-rep max from a single set. Warm-ups and sets over
/// `TrainingConstants.maxRepsForOneRepMax` reps are not eligible.
public enum OneRepMax {
    public enum Formula: CaseIterable, Sendable {
        case epley, brzycki, wathen
    }

    /// Estimate using one formula. Returns nil for reps outside 1...12 or a
    /// non-positive weight. A single rep is the max itself.
    public static func estimate(weight: Double, reps: Int, formula: Formula) -> Double? {
        guard isEligible(weight: weight, reps: reps) else { return nil }
        if reps == 1 { return weight }
        let r = Double(reps)
        switch formula {
        case .epley:
            return weight * (1 + r / 30)
        case .brzycki:
            return weight * 36 / (37 - r)
        case .wathen:
            return 100 * weight / (48.8 + 53.8 * exp(-0.075 * r))
        }
    }

    /// The app's e1RM: the mean of Epley, Brzycki and Wathen.
    public static func estimate(weight: Double, reps: Int) -> Double? {
        let values = Formula.allCases.compactMap { estimate(weight: weight, reps: reps, formula: $0) }
        guard values.count == Formula.allCases.count else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// e1RM with an RIR adjustment: reps left in the tank count as reps to failure.
    public static func estimate(weight: Double, reps: Int, repsInReserve: Int) -> Double? {
        estimate(weight: weight, reps: reps + max(0, repsInReserve))
    }

    public static func isEligible(weight: Double, reps: Int) -> Bool {
        weight > 0 && reps >= 1 && reps <= TrainingConstants.maxRepsForOneRepMax
    }
}
