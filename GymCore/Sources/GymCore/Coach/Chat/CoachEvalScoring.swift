import Foundation

/// The arithmetic behind the coach-chat evaluation harness: how far a proposed working weight
/// sits from the lifter's recent best, and whether the proposed weekly set count per muscle
/// lands in the band the scenario expects. Pure so the numbers can be pinned without a store
/// or a model; the hosted eval suite feeds it seeded history and validated drafts.
public enum CoachEvalScoring {
    /// One logged working set, as the seeded history knows it.
    public struct HistorySet: Hashable, Sendable {
        public var exercise: String
        public var primaryMuscles: [Muscle]
        public var weightKg: Double
        public var reps: Int
        public var date: Date

        public init(exercise: String, primaryMuscles: [Muscle], weightKg: Double, reps: Int, date: Date) {
            self.exercise = exercise
            self.primaryMuscles = primaryMuscles
            self.weightKg = weightKg
            self.reps = reps
            self.date = date
        }
    }

    /// One exercise as a proposal programs it, already resolved against the library.
    public struct ProposedExercise: Hashable, Sendable {
        public var exercise: String
        public var primaryMuscles: [Muscle]
        public var workingSets: Int
        /// The heaviest working-set target; nil when the proposal left weight out.
        public var weightKg: Double?
        /// How many times a week the routine holding it is performed.
        public var timesPerWeek: Double

        public init(
            exercise: String, primaryMuscles: [Muscle], workingSets: Int, weightKg: Double?,
            timesPerWeek: Double = 1
        ) {
            self.exercise = exercise
            self.primaryMuscles = primaryMuscles
            self.workingSets = workingSets
            self.weightKg = weightKg
            self.timesPerWeek = timesPerWeek
        }
    }

    // MARK: - Weights

    /// Where a proposed weight is allowed to sit against the recent best: the prompt asks for
    /// 5–10% under, so a little under that and a little over it are both still "used the
    /// lifter's numbers". Percent of the best.
    public static let acceptableDeviationPercent = -15.0...5.0

    public struct WeightCheck: Hashable, Sendable {
        public var exercise: String
        public var proposedKg: Double
        public var bestKg: Double
        /// `(proposed − best) / best × 100`: negative is lighter than the best.
        public var deviationPercent: Double

        public func isAcceptable(in band: ClosedRange<Double> = acceptableDeviationPercent) -> Bool {
            band.contains(deviationPercent)
        }
    }

    /// The heaviest working set per exercise (case-insensitive name) on or after `since`.
    public static func recentBestsKg(history: [HistorySet], since: Date) -> [String: Double] {
        var bests: [String: Double] = [:]
        for set in history where set.date >= since && set.weightKg > 0 {
            let key = set.exercise.lowercased()
            bests[key] = max(bests[key] ?? 0, set.weightKg)
        }
        return bests
    }

    /// One check per proposed exercise that has both a weight and a recent best; exercises
    /// without history are the model's call and are not scored here.
    public static func weightChecks(
        proposed: [ProposedExercise], bestsKg: [String: Double]
    ) -> [WeightCheck] {
        proposed.compactMap { exercise in
            guard let proposedKg = exercise.weightKg, let best = bestsKg[exercise.exercise.lowercased()],
                  best > 0 else { return nil }
            return WeightCheck(
                exercise: exercise.exercise, proposedKg: proposedKg, bestKg: best,
                deviationPercent: (proposedKg - best) / best * 100
            )
        }
    }

    /// Fraction of checks inside the band; nil when there was nothing to check. A scenario
    /// widens the band when a lighter start is the right call (a lifter back from a layoff).
    public static func weightScore(
        _ checks: [WeightCheck], band: ClosedRange<Double> = acceptableDeviationPercent
    ) -> Double? {
        guard !checks.isEmpty else { return nil }
        return Double(checks.filter { $0.isAcceptable(in: band) }.count) / Double(checks.count)
    }

    /// The largest absolute deviation, for the one-line summary; nil with nothing to check.
    public static func worstDeviationPercent(_ checks: [WeightCheck]) -> Double? {
        checks.map(\.deviationPercent).max { abs($0) < abs($1) }
    }

    // MARK: - Volume

    /// What the scenario expects of the proposed weekly volume against the recent week.
    public enum VolumeExpectation: String, Codable, Sendable {
        /// An under-recovered lifter: not more than they were doing.
        case atMostRecent = "at_most_recent"
        /// A beginner or a returner with room: not less than they were doing.
        case atLeastRecent = "at_least_recent"
        /// Anything sane; only reported.
        case any
    }

    public enum VolumeVerdict: String, Codable, Sendable {
        case ok, high, low
        /// No proposal carried sets, so there is nothing to compare.
        case none
    }

    public struct VolumeCheck: Hashable, Sendable {
        public var muscle: Muscle
        public var recentWeeklySets: Double
        public var proposedWeeklySets: Double
    }

    /// Proposed weekly working sets per primary muscle: each exercise's sets times how often
    /// its routine runs, split evenly across its primary muscles.
    public static func proposedWeeklySets(_ proposed: [ProposedExercise]) -> [Muscle: Double] {
        var sets: [Muscle: Double] = [:]
        for exercise in proposed where !exercise.primaryMuscles.isEmpty {
            let share = Double(exercise.workingSets) * exercise.timesPerWeek
                / Double(exercise.primaryMuscles.count)
            for muscle in exercise.primaryMuscles { sets[muscle, default: 0] += share }
        }
        return sets
    }

    /// Logged working sets per primary muscle in the seven days before `now`, split evenly
    /// across each set's primary muscles.
    public static func recentWeeklySets(history: [HistorySet], now: Date) -> [Muscle: Double] {
        let since = now.addingTimeInterval(-7 * 86_400)
        var sets: [Muscle: Double] = [:]
        for set in history where set.date >= since && set.date <= now && !set.primaryMuscles.isEmpty {
            let share = 1 / Double(set.primaryMuscles.count)
            for muscle in set.primaryMuscles { sets[muscle, default: 0] += share }
        }
        return sets
    }

    /// Per-muscle comparison over the union of muscles, sorted by name.
    public static func volumeChecks(recent: [Muscle: Double], proposed: [Muscle: Double]) -> [VolumeCheck] {
        Set(recent.keys).union(proposed.keys).sorted { $0.rawValue < $1.rawValue }.map { muscle in
            VolumeCheck(
                muscle: muscle, recentWeeklySets: recent[muscle] ?? 0,
                proposedWeeklySets: proposed[muscle] ?? 0
            )
        }
    }

    /// The overall verdict on total weekly sets: `high` when the proposal is more than 20% (and
    /// more than two sets) above the recent week, `low` when more than 20% (and two sets)
    /// below, `ok` between. Totals rather than per-muscle so one swapped accessory does not
    /// fail a plan that holds the week's work steady.
    public static func volumeVerdict(recent: [Muscle: Double], proposed: [Muscle: Double]) -> VolumeVerdict {
        let recentTotal = recent.values.reduce(0, +)
        let proposedTotal = proposed.values.reduce(0, +)
        guard proposedTotal > 0 else { return .none }
        let difference = proposedTotal - recentTotal
        if difference > max(2, recentTotal * 0.2) { return .high }
        if difference < -max(2, recentTotal * 0.2) { return .low }
        return .ok
    }

    /// Whether the verdict satisfies the expectation; nil when there was no proposal to judge.
    public static func volumeScore(_ verdict: VolumeVerdict, expectation: VolumeExpectation) -> Double? {
        switch (verdict, expectation) {
        case (.none, _): nil
        case (.high, .atMostRecent), (.low, .atLeastRecent): 0
        default: 1
        }
    }

    // MARK: - Evidence (heuristic)

    /// Fraction of keyword groups the reply mentions (any word of a group counts). A keyword
    /// heuristic, not a judgement of the reasoning — labelled as such in the report.
    public static func evidenceScore(reply: String, keywordGroups: [[String]]) -> Double? {
        guard !keywordGroups.isEmpty else { return nil }
        let text = reply.lowercased()
        let hits = keywordGroups.filter { group in group.contains { text.contains($0.lowercased()) } }
        return Double(hits.count) / Double(keywordGroups.count)
    }
}
