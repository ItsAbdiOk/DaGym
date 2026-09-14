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

    /// **The canonical e1RM**: the mean of Epley, Brzycki and Wathen.
    ///
    /// Every e1RM the lifter is shown — the PR banner and cache, the exercise card, the
    /// sparkline, the progress charts, the coach and the linear progression rule — comes from
    /// this one function, so a number on one screen is the same number on the next.
    ///
    /// The single deliberate exception is `RPELoad.e1RM`, a pure Epley with an RIR term. That
    /// rule *inverts* its e1RM to solve for the next load, and only Epley is invertible in
    /// closed form; mixing three formulas there would make the rule's own arithmetic
    /// inconsistent. It is documented at its use site (`ProgressionEngine+RPE`).
    public static func estimate(weight: Double, reps: Int) -> Double? {
        let values = Formula.allCases.compactMap { estimate(weight: weight, reps: reps, formula: $0) }
        guard values.count == Formula.allCases.count else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// e1RM with an RIR adjustment: reps left in the tank count as reps to failure.
    ///
    /// The RIR-extended rep count is clamped to `TrainingConstants.maxRepsForOneRepMax` rather
    /// than falling off the eligible range. It used to return nil past 12: 100 × 8 at RPE 5
    /// (RIR 5 → 13 reps) produced *no* e1RM while the same set left unrated produced one, so
    /// rating a set could silently delete it from the progression rule's baseline and drop the
    /// deload's "90 % of e1RM" onto a different basis. Clamping keeps a rated set at least as
    /// strong as the unrated reading of itself, which is the direction the adjustment means.
    public static func estimate(weight: Double, reps: Int, repsInReserve: Int) -> Double? {
        guard isEligible(weight: weight, reps: reps) else { return nil }
        let adjusted = min(reps + max(0, repsInReserve), TrainingConstants.maxRepsForOneRepMax)
        return estimate(weight: weight, reps: adjusted)
    }

    public static func isEligible(weight: Double, reps: Int) -> Bool {
        weight > 0 && reps >= 1 && reps <= TrainingConstants.maxRepsForOneRepMax
    }
}
