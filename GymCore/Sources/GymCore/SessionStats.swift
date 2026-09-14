import Foundation

/// Summary numbers computed from a workout's completed sets.
public enum SessionStats {
    /// A secondary mover counts at this fraction of a primary mover. **The** weight — every
    /// other secondary-vs-primary calculation in the app reads this constant rather than
    /// carrying its own copy (`BodySeries.setsPerMuscle`, `RoutineMuscles.hitMap`,
    /// `ExerciseInfo.hitMap`, `Recovery.secondaryShare`).
    ///
    /// Why 0.45 and not 0.5: the body map's four-step coral ramp buckets an intensity with
    /// `Int((value * 3).rounded())`, so anything at or above 0.5 rounds onto step 2 of 3 — a
    /// secondary mover would read as very nearly a primary one. 0.45 lands on step 1, the
    /// lightest tinted step, which is what "this muscle helped" should look like. The two
    /// values used to disagree (0.45 here, 0.5 in the stats), so the same exercise's secondary
    /// muscle rendered two steps darker on a routine card than on its own library row.
    public static let secondaryMuscleShare = 0.45

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
            let primary = Set(entry.primary)
            for muscle in entry.primary {
                raw[muscle, default: 0] += count
            }
            // A muscle listed as both a primary and a secondary mover of the same exercise
            // counts once, as a primary. The seed data no longer does this, but a
            // user-authored or imported exercise still can, and counting it at 1.5 sets
            // silently inflated whatever muscle happened to be duplicated.
            for muscle in entry.secondary where !primary.contains(muscle) {
                raw[muscle, default: 0] += count * secondaryMuscleShare
            }
        }
        guard let maxScore = raw.values.max(), maxScore > 0 else { return [:] }
        return raw.mapValues { min(1.0, $0 / maxScore) }
    }
    // swiftlint:enable large_tuple
}
