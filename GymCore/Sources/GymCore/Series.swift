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
        fileprivate var hardSetCount: Int { sets.count(where: { $0.kind.countsTowardStats && $0.isHard }) }
    }

    fileprivate var volumeKg: Double {
        entries.flatMap(\.sets)
            .filter { $0.kind.countsTowardStats }
            .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    }
}

/// The horizon a balance ("sets per muscle") map is drawn over.
public enum BalanceWindow: Sendable, Hashable {
    /// The trailing `days` days ending at `now`.
    case days(Int)
    /// The current week of `calendar` (its `firstWeekday` decides where the week starts) — pass
    /// the training calendar so "this week" means the training week everywhere.
    case thisWeek(Calendar)
    /// Every workout ever logged.
    case allTime

    /// Whether `date` falls inside this window as seen from `now`.
    public func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard date <= now else { return false }
        switch self {
        case .days(let days):
            guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return false }
            return date >= cutoff
        case .thisWeek(let weekCalendar):
            guard let week = weekCalendar.dateInterval(of: .weekOfYear, for: now) else { return false }
            return week.contains(date)
        case .allTime:
            return true
        }
    }

    /// The earliest date a caller needs to fetch to cover this window; nil for `.allTime`.
    public func earliestDate(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .days(let days): calendar.date(byAdding: .day, value: -days, to: now)
        case .thisWeek(let weekCalendar): weekCalendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .allTime: nil
        }
    }
}

/// Body-wide chart series (plan.md §6.4): weekly volume, sets per muscle, session durations.
public enum BodySeries {
    /// A secondary mover counts at this fraction of a primary mover — see
    /// `SessionStats.secondaryMuscleShare`, the one place that weight is defined.
    private static let secondaryMuscleShare = SessionStats.secondaryMuscleShare
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
    /// secondary movers `SessionStats.secondaryMuscleShare`. Raw totals, not normalised —
    /// callers scale for display.
    public static func setsPerMuscle(
        workouts: [BodyWorkout], days: Int, now: Date, calendar: Calendar
    ) -> [Muscle: Double] {
        setsPerMuscle(workouts: workouts, window: .days(days), now: now, calendar: calendar)
    }

    /// Sets per muscle inside `window` (primary 1, secondary
    /// `SessionStats.secondaryMuscleShare`). With `hardOnly` only sets
    /// rated RIR ≤ `TrainingConstants.hardSetMaxRIR`, or taken to failure / AMRAP, count —
    /// "where did the near-failure work go" rather than "where did the volume go".
    public static func setsPerMuscle(
        workouts: [BodyWorkout], window: BalanceWindow, now: Date, calendar: Calendar,
        hardOnly: Bool = false
    ) -> [Muscle: Double] {
        var totals: [Muscle: Double] = [:]
        for workout in workouts where window.contains(workout.date, now: now, calendar: calendar) {
            for entry in workout.entries {
                let count = Double(hardOnly ? entry.hardSetCount : entry.countingSetCount)
                guard count > 0 else { continue }
                let primary = Set(entry.primary)
                for muscle in entry.primary { totals[muscle, default: 0] += count }
                // Primary wins: a muscle listed in both lists counts once, as a primary.
                for muscle in entry.secondary where !primary.contains(muscle) {
                    totals[muscle, default: 0] += count * secondaryMuscleShare
                }
            }
        }
        return totals
    }

    /// Every workout's duration, oldest first, for a duration-over-time chart.
    public static func sessionDurations(workouts: [BodyWorkout]) -> [(date: Date, durationSeconds: Int)] {
        workouts.sorted { $0.date < $1.date }.map { (date: $0.date, durationSeconds: $0.durationSeconds) }
    }
}

/// One calendar week's effort picture: the mean rating across rated counting sets and how
/// many of the week's counting sets carried a rating at all.
public struct EffortWeek: Sendable, Equatable {
    public var weekStart: Date
    /// Mean RPE of the rated sets — canonical, like `Effort.rpe`.
    public var meanRPE: Double
    public var ratedSets: Int
    public var totalSets: Int

    public init(weekStart: Date, meanRPE: Double, ratedSets: Int, totalSets: Int) {
        self.weekStart = weekStart
        self.meanRPE = meanRPE
        self.ratedSets = ratedSets
        self.totalSets = totalSets
    }

    /// Share of counting sets that were rated, 0…1.
    public var coverage: Double {
        totalSets > 0 ? Double(ratedSets) / Double(totalSets) : 0
    }

    /// The mean in the lifter's scale: RPE as is, RIR as 10 − RPE.
    public func meanValue(scale: Effort.Scale) -> Double {
        switch scale {
        case .rpe: meanRPE
        case .rir: 10 - meanRPE
        }
    }
}

/// Body-wide effort series (features.md adopt 9): mean rating per week and a hardest-first
/// histogram, over completed non-warm-up sets that carry a rating.
public enum EffortSeries {
    /// Mean rating per calendar week (`calendar.firstWeekday` decides the week), oldest first.
    /// Only weeks with at least one counting set appear; a week with counting sets but no
    /// rating still appears (coverage 0, `meanRPE` 0) so the coverage line stays honest.
    public static func weeklyEffort(workouts: [BodyWorkout], calendar: Calendar) -> [EffortWeek] {
        var rpeSum: [Date: Double] = [:]
        var rated: [Date: Int] = [:]
        var total: [Date: Int] = [:]
        for workout in workouts {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: workout.date)?.start else {
                continue
            }
            for set in workout.entries.flatMap(\.sets) where set.kind.countsTowardStats {
                total[weekStart, default: 0] += 1
                guard let rpe = set.rpe else { continue }
                rated[weekStart, default: 0] += 1
                rpeSum[weekStart, default: 0] += Effort(rpe: rpe).rpe
            }
        }
        return total.keys.sorted().map { weekStart in
            let ratedCount = rated[weekStart] ?? 0
            let mean = ratedCount > 0 ? (rpeSum[weekStart] ?? 0) / Double(ratedCount) : 0
            return EffortWeek(
                weekStart: weekStart, meanRPE: mean, ratedSets: ratedCount, totalSets: total[weekStart] ?? 0
            )
        }
    }

    /// Rated counting sets per `Effort.steps` bin, hardest (RPE 10) first. Every bin is
    /// present so the chart's axis is stable; half-step ratings round to the nearest step.
    public static func histogram(workouts: [BodyWorkout]) -> [(effort: Effort, count: Int)] {
        var counts: [Int: Int] = [:]
        for set in workouts.flatMap(\.entries).flatMap(\.sets) where set.kind.countsTowardStats {
            guard let rpe = set.rpe else { continue }
            counts[Int(Effort(rpe: rpe).rpe.rounded()), default: 0] += 1
        }
        return Effort.steps.reversed().map { (effort: $0, count: counts[Int($0.rpe)] ?? 0) }
    }

    /// How many counting sets carry a rating at all — the card stays hidden while this is 0.
    public static func ratedSetCount(workouts: [BodyWorkout]) -> Int {
        workouts.flatMap(\.entries).flatMap(\.sets).count { $0.kind.countsTowardStats && $0.rpe != nil }
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
