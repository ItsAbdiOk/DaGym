import Foundation

/// Summary numbers computed from a workout's completed sets.
public enum SessionStats {
    /// A secondary mover counts at this fraction of a primary mover — our own weight, the same
    /// convention `BodySeries.setsPerMuscle` uses.
    private static let secondaryMuscleShare = 0.5

    /// Total weight × reps across completed, non-warm-up sets. Bodyweight
    /// styles logged with zero weight contribute zero.
    public static func volumeKg(_ sets: [PerformedSet]) -> Double {
        sets.filter { $0.kind.countsTowardStats }
            .reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    // swiftlint:disable large_tuple
    /// How much each muscle was worked this session, normalised so the most
    /// worked muscle is 1.0; secondary muscles count at half weight.
    public static func musclesHit(
        sets: [(primary: [Muscle], secondary: [Muscle], completedCount: Int)]
    ) -> [Muscle: Double] {
        var raw: [Muscle: Double] = [:]
        for entry in sets {
            let count = Double(entry.completedCount)
            for muscle in entry.primary {
                raw[muscle, default: 0] += count
            }
            for muscle in entry.secondary {
                raw[muscle, default: 0] += count * secondaryMuscleShare
            }
        }
        guard let maxScore = raw.values.max(), maxScore > 0 else { return [:] }
        return raw.mapValues { min(1.0, $0 / maxScore) }
    }
    // swiftlint:enable large_tuple
}
