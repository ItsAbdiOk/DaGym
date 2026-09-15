import Foundation

/// One training session's completed sets for an exercise, the shared input shape for
/// `ExerciseSeries`. Callers group their raw logs by session date before calling in.
public struct ExerciseSession: Sendable {
    public var date: Date
    public var sets: [PerformedSet]

    public init(date: Date, sets: [PerformedSet]) {
        self.date = date
        self.sets = sets
    }

    /// Completed, non-warm-up sets — the only ones that count toward any series.
    fileprivate var countingSets: [PerformedSet] {
        sets.filter { $0.kind.countsTowardStats }
    }
}

/// Per-exercise chart series (plan.md §6.4): e1RM, top set, volume and reps-at-weight, one
/// point per session that has eligible data. Pure over `[ExerciseSession]` — no I/O, no dates
/// beyond what's passed in.
public enum ExerciseSeries {
    /// Best estimated one-rep max per session (`OneRepMax.estimate`, sets 1…12 reps,
    /// non-warm-up). Sessions with no eligible set are omitted rather than charted as zero.
    ///
    /// Estimated from `PerformedSet.effectiveWeightKg`, the same load the PR cache uses — this
    /// used to read the raw `weightKg`, so a +20 kg pull-up charted a point of 23 while the
    /// exercise card quoted 117 from the PR cache for the very same set, and the coach's e1RM
    /// downtrend rule watched the 23-series.
    public static func e1rm(sessions: [ExerciseSession]) -> [(date: Date, value: Double)] {
        sessions.compactMap { session in
            let best = session.countingSets
                .compactMap { set in
                    set.effectiveWeightKg.flatMap { OneRepMax.estimate(weight: $0, reps: set.reps) }
                }
                .max()
            return best.map { (date: session.date, value: $0) }
        }
    }

    /// The heaviest set of the session: its weight, ties broken by the higher rep count (the
    /// reps don't change the plotted value, only which set is "the" top set).
    public static func topSet(sessions: [ExerciseSession]) -> [(date: Date, value: Double)] {
        sessions.compactMap { session in
            let best = session.countingSets.max { lhs, rhs in
                lhs.weightKg == rhs.weightKg ? lhs.reps < rhs.reps : lhs.weightKg < rhs.weightKg
            }
            return best.map { (date: session.date, value: $0.weightKg) }
        }
    }

    /// Total weight × reps per session across completed, non-warm-up sets. Every session gets a
    /// point (zero when it has none), so the chart's x-axis stays continuous.
    public static func volume(sessions: [ExerciseSession]) -> [(date: Date, value: Double)] {
        sessions.map { session in
            let total = session.countingSets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
            return (date: session.date, value: total)
        }
    }

    /// Reps performed at (approximately) `weight` per session — the best (highest-rep) matching
    /// set when there's more than one. Sessions with no matching set are omitted.
    public static func repsAtWeight(
        sessions: [ExerciseSession], weight: Double, tolerance: Double = 0.01
    ) -> [(date: Date, value: Int)] {
        sessions.compactMap { session in
            let matching = session.countingSets
                .filter { abs($0.weightKg - weight) <= tolerance }
                .map(\.reps)
                .max()
            return matching.map { (date: session.date, value: $0) }
        }
    }

    /// The weight that appears most often across a history of sessions, for defaulting the
    /// reps-at-weight picker. Nil when there are no counting sets at all.
    public static func mostCommonWeight(sessions: [ExerciseSession]) -> Double? {
        var counts: [Double: Int] = [:]
        for session in sessions {
            for set in session.countingSets {
                counts[set.weightKg, default: 0] += 1
            }
        }
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
        }?.key
    }
}

extension ExerciseSeries {
    /// The rating on each session's top set (`topSet`'s pick), keyed by session date, for
    /// tinting the top-set line's dots. Sessions whose top set was unrated are absent.
    public static func topSetRPE(sessions: [ExerciseSession]) -> [Date: Double] {
        var ratings: [Date: Double] = [:]
        for session in sessions {
            let best = session.countingSets.max { lhs, rhs in
                lhs.weightKg == rhs.weightKg ? lhs.reps < rhs.reps : lhs.weightKg < rhs.weightKg
            }
            if let rpe = best?.rpe { ratings[session.date] = rpe }
        }
        return ratings
    }

    /// True when no counting set across the history carries a load — a bodyweight move whose
    /// weight charts would be flat zeros, so the chart plots reps instead.
    public static func isNeverLoaded(sessions: [ExerciseSession]) -> Bool {
        let counting = sessions.flatMap(\.countingSets)
        return !counting.isEmpty && counting.allSatisfy { $0.weightKg == 0 }
    }

    /// Best (highest-rep) counting set per session. Sessions with no counting set are omitted.
    public static func bestReps(sessions: [ExerciseSession]) -> [(date: Date, value: Int)] {
        sessions.compactMap { session in
            session.countingSets.map(\.reps).max().map { (date: session.date, value: $0) }
        }
    }

    /// Total reps per session across counting sets; every session gets a point, like `volume`.
    public static func totalReps(sessions: [ExerciseSession]) -> [(date: Date, value: Int)] {
        sessions.map { session in
            (date: session.date, value: session.countingSets.reduce(0) { $0 + $1.reps })
        }
    }
}
