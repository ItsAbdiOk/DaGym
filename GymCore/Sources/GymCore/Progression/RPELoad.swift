import Foundation

/// RPE/RIR-based load math (plan.md §7). Unlike `OneRepMax`, this form is
/// invertible: it folds RIR into the Epley formula so a load can be solved
/// back out for a different target rep/RPE combination.
public enum RPELoad {
    /// Reps-to-failure implied by a completed set: reps actually done plus
    /// however many were left in the tank at that RPE.
    public static func repsToFailure(reps: Int, rpe: Double) -> Double {
        Double(reps) + (10 - rpe)
    }

    /// Estimated 1RM from one completed set, via the invertible Epley form.
    public static func e1RM(weight: Double, reps: Int, rpe: Double) -> Double {
        weight * (1 + repsToFailure(reps: reps, rpe: rpe) / 30)
    }

    /// The load that should produce `targetReps` at `targetRPE`, derived from
    /// a completed set's implied e1RM.
    public static func nextLoad(
        fromWeightKg weight: Double,
        reps: Int,
        rpe: Double,
        targetReps: Int,
        targetRPE: Double
    ) -> Double {
        let estimated1RM = e1RM(weight: weight, reps: reps, rpe: rpe)
        let targetFailureReps = Double(targetReps) + (10 - targetRPE)
        return estimated1RM / (1 + targetFailureReps / 30)
    }
}
