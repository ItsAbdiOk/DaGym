import Foundation

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
