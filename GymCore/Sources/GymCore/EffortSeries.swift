import Foundation

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
