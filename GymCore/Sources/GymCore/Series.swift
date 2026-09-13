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
    /// Best estimated one-rep max per session (`OneRepMax`, sets 1…12 reps, non-warm-up).
    /// Sessions with no eligible set are omitted rather than charted as zero.
    public static func e1rm(sessions: [ExerciseSession]) -> [(date: Date, value: Double)] {
        sessions.compactMap { session in
            let best = session.countingSets
                .compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }
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

/// One finished workout's sets across every exercise, grouped for body-wide series.
public struct BodyWorkout: Sendable {
    public var date: Date
    public var durationSeconds: Int
    public var entries: [MuscleEntry]

    public init(date: Date, durationSeconds: Int, entries: [MuscleEntry]) {
        self.date = date
        self.durationSeconds = durationSeconds
        self.entries = entries
    }

    /// One exercise's contribution: its primary/secondary muscles and its counting sets.
    public struct MuscleEntry: Sendable {
        public var primary: [Muscle]
        public var secondary: [Muscle]
        public var sets: [PerformedSet]

        public init(primary: [Muscle], secondary: [Muscle], sets: [PerformedSet]) {
            self.primary = primary
            self.secondary = secondary
            self.sets = sets
        }

        fileprivate var countingSetCount: Int { sets.count(where: { $0.kind.countsTowardStats }) }
    }

    fileprivate var volumeKg: Double {
        entries.flatMap(\.sets)
            .filter { $0.kind.countsTowardStats }
            .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    }
}

/// Body-wide chart series (plan.md §6.4): weekly volume, sets per muscle, session durations.
public enum BodySeries {
    /// Total volume per calendar week, bucketed by `calendar.dateInterval(of: .weekOfYear:)` —
    /// honours the caller's `calendar.firstWeekday`. Only weeks with at least one workout appear,
    /// sorted oldest first.
    public static func weeklyVolume(
        workouts: [BodyWorkout], calendar: Calendar
    ) -> [(weekStart: Date, volumeKg: Double)] {
        var totals: [Date: Double] = [:]
        for workout in workouts {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: workout.date)?.start else {
                continue
            }
            totals[weekStart, default: 0] += workout.volumeKg
        }
        return totals.sorted { $0.key < $1.key }.map { (weekStart: $0.key, volumeKg: $0.value) }
    }

    /// Sets per muscle over the trailing `days` days ending at `now`: primary movers count 1,
    /// secondary movers 0.5. Raw totals, not normalised — callers scale for display.
    public static func setsPerMuscle(
        workouts: [BodyWorkout], days: Int, now: Date, calendar: Calendar
    ) -> [Muscle: Double] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return [:] }
        var totals: [Muscle: Double] = [:]
        for workout in workouts where workout.date >= cutoff && workout.date <= now {
            for entry in workout.entries {
                let count = Double(entry.countingSetCount)
                guard count > 0 else { continue }
                for muscle in entry.primary { totals[muscle, default: 0] += count }
                for muscle in entry.secondary { totals[muscle, default: 0] += count * 0.5 }
            }
        }
        return totals
    }

    /// Every workout's duration, oldest first, for a duration-over-time chart.
    public static func sessionDurations(workouts: [BodyWorkout]) -> [(date: Date, durationSeconds: Int)] {
        workouts.sorted { $0.date < $1.date }.map { (date: $0.date, durationSeconds: $0.durationSeconds) }
    }
}
