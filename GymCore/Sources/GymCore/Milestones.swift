import Foundation

/// Bronze/silver/gold tier, ordered low to high.
public enum Tier: Int, CaseIterable, Comparable, Hashable, Sendable {
    case bronze, silver, gold

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }
}

/// What a milestone tracks. `strengthRatio` needs a bodyweight reading to evaluate — thresholds
/// for it are expressed as a multiple of bodyweight, everything else as a raw count/total.
public enum MilestoneMetric: Equatable, Sendable {
    /// e1RM ÷ bodyweight for one of the four tracked lifts, keyed "bench"/"squat"/"deadlift"/"ohp".
    case strengthRatio(exerciseKey: String)
    case workoutCount
    case streakWeeks
    case lifetimeTonnageKg
    /// Weeks the weekly training-frequency goal was met.
    case consistencyWeeks
}

/// One milestone's identity, title and tier thresholds. Data-driven so new milestones are just
/// another entry in `Milestones.definitions`.
public struct MilestoneDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let metric: MilestoneMetric
    public let tiers: [(tier: Tier, threshold: Double)]

    public init(
        id: String, title: String, metric: MilestoneMetric, tiers: [(tier: Tier, threshold: Double)]
    ) {
        self.id = id
        self.title = title
        self.metric = metric
        self.tiers = tiers
    }

    /// The threshold for a given tier, or nil if this definition doesn't define one.
    public func threshold(for tier: Tier) -> Double? {
        tiers.first { $0.tier == tier }?.threshold
    }
}

/// The lifter's current numbers, gathered by `WorkoutStore.milestoneState()`.
public struct MilestoneState: Sendable {
    public var workoutCount: Int
    public var streakWeeks: Int
    public var lifetimeTonnageKg: Double
    public var consistentWeeks: Int
    public var bodyweightKg: Double?
    /// Best known e1RM per `strengthRatio` exercise key.
    public var bestE1RM: [String: Double]

    public init(
        workoutCount: Int, streakWeeks: Int, lifetimeTonnageKg: Double, consistentWeeks: Int,
        bodyweightKg: Double? = nil, bestE1RM: [String: Double] = [:]
    ) {
        self.workoutCount = workoutCount
        self.streakWeeks = streakWeeks
        self.lifetimeTonnageKg = lifetimeTonnageKg
        self.consistentWeeks = consistentWeeks
        self.bodyweightKg = bodyweightKg
        self.bestE1RM = bestE1RM
    }
}

/// One newly-earned tier of a milestone.
public struct Achievement: Identifiable, Hashable, Sendable {
    public var id: String
    public var tier: Tier
    public var title: String
    public var line: String

    public init(id: String, tier: Tier, title: String, line: String) {
        self.id = id
        self.tier = tier
        self.title = title
        self.line = line
    }
}

/// Where a lifter stands on one milestone right now — used to draw the "locked" progress card
/// regardless of what's actually been earned/persisted yet.
public struct MilestoneProgress: Identifiable, Sendable {
    public var id: String { definition.id }
    public var definition: MilestoneDefinition
    /// The highest tier the current numbers qualify for, nil if none yet (or the metric can't be
    /// evaluated, e.g. a strength ratio with no bodyweight on file).
    public var currentTier: Tier?
    /// The threshold of the next tier to chase, nil once gold is reached.
    public var nextThreshold: Double?
    /// 0...1 toward `nextThreshold`; 1.0 once every tier is earned.
    public var progress: Double
    /// The raw metric value right now (a ratio for `strengthRatio`, a count/kg otherwise), nil
    /// when it can't be evaluated yet (e.g. no bodyweight on file).
    public var currentValue: Double?

    public init(
        definition: MilestoneDefinition, currentTier: Tier?, nextThreshold: Double?, progress: Double,
        currentValue: Double? = nil
    ) {
        self.definition = definition
        self.currentTier = currentTier
        self.nextThreshold = nextThreshold
        self.progress = progress
        self.currentValue = currentValue
    }
}

/// Auto-detected bronze/silver/gold milestones (plan.md §6.4, §7). Thresholds below are the
/// app's own — not a copy of any proprietary strength-standard table.
public enum Milestones {
    public static let definitions: [MilestoneDefinition] = [
        strengthDefinition(key: "bench", title: "Bodyweight Bench", bronze: 0.75, silver: 1.0, gold: 1.25),
        strengthDefinition(key: "squat", title: "Bodyweight Squat", bronze: 1.0, silver: 1.5, gold: 2.0),
        strengthDefinition(
            key: "deadlift", title: "Bodyweight Deadlift", bronze: 1.25, silver: 1.75, gold: 2.25
        ),
        strengthDefinition(
            key: "ohp", title: "Bodyweight Overhead Press", bronze: 0.5, silver: 0.75, gold: 1.0
        ),
        MilestoneDefinition(
            id: "workoutCount", title: "Workout Count", metric: .workoutCount,
            tiers: [(.bronze, 10), (.silver, 50), (.gold, 200)]
        ),
        MilestoneDefinition(
            id: "streakWeeks", title: "Weekly Streak", metric: .streakWeeks,
            tiers: [(.bronze, 4), (.silver, 12), (.gold, 26)]
        ),
        MilestoneDefinition(
            id: "lifetimeTonnage", title: "Lifetime Tonnage", metric: .lifetimeTonnageKg,
            tiers: [(.bronze, 100_000), (.silver, 500_000), (.gold, 2_000_000)]
        ),
        MilestoneDefinition(
            id: "consistencyWeeks", title: "Consistency", metric: .consistencyWeeks,
            tiers: [(.bronze, 8), (.silver, 26), (.gold, 52)]
        )
    ]

    private static func strengthDefinition(
        key: String, title: String, bronze: Double, silver: Double, gold: Double
    ) -> MilestoneDefinition {
        MilestoneDefinition(
            id: "strength.\(key)", title: title, metric: .strengthRatio(exerciseKey: key),
            tiers: [(.bronze, bronze), (.silver, silver), (.gold, gold)]
        )
    }

    /// Newly earned tiers only — at most one `Achievement` per definition, the highest tier
    /// crossed since `earned`. A milestone already at its highest already-earned tier, or whose
    /// metric can't be evaluated (e.g. a strength ratio with no bodyweight on file), is skipped.
    public static func evaluate(
        state: MilestoneState, earned: [(id: String, tier: Tier)]
    ) -> [Achievement] {
        let earnedTiers = Dictionary(earned.map { ($0.id, $0.tier) }, uniquingKeysWith: { max($0, $1) })
        return definitions.compactMap { definition -> Achievement? in
            guard let achieved = highestAchievedTier(definition, state: state) else { return nil }
            if let previous = earnedTiers[definition.id], achieved <= previous { return nil }
            return Achievement(
                id: definition.id, tier: achieved, title: definition.title,
                line: line(for: definition, tier: achieved, state: state)
            )
        }
    }

    /// Where the lifter stands on every milestone right now, for the "locked" progress cards —
    /// independent of what's been persisted as earned so far.
    public static func progress(state: MilestoneState) -> [MilestoneProgress] {
        definitions.map { definition in
            let currentTier = highestAchievedTier(definition, state: state)
            let nextTier = Tier.allCases.first { $0.rawValue > (currentTier?.rawValue ?? -1) }
            let nextThreshold = nextTier.flatMap(definition.threshold(for:))
            let value = currentValue(for: definition.metric, state: state)
            let fraction = progressFraction(
                definition: definition, currentTier: currentTier, nextThreshold: nextThreshold, value: value
            )
            return MilestoneProgress(
                definition: definition, currentTier: currentTier, nextThreshold: nextThreshold,
                progress: fraction, currentValue: value
            )
        }
    }

    private static func progressFraction(
        definition: MilestoneDefinition, currentTier: Tier?, nextThreshold: Double?, value: Double?
    ) -> Double {
        guard let nextThreshold else { return 1 }
        guard let value else { return 0 }
        let previousThreshold = currentTier.flatMap(definition.threshold(for:)) ?? 0
        let span = nextThreshold - previousThreshold
        guard span > 0 else { return value >= nextThreshold ? 1 : 0 }
        return min(1, max(0, (value - previousThreshold) / span))
    }

    /// A workout logged more than an hour before `now` is treated as backfilled/past and never
    /// celebration-worthy — our own heuristic, since a live `finish()` call happens moments after
    /// the workout itself ends.
    public static func isCelebrationWorthy(workoutDate: Date, now: Date) -> Bool {
        let delay = now.timeIntervalSince(workoutDate)
        return delay >= 0 && delay <= 3600
    }

    private static func highestAchievedTier(
        _ definition: MilestoneDefinition, state: MilestoneState
    ) -> Tier? {
        guard let currentValue = currentValue(for: definition.metric, state: state) else { return nil }
        return definition.tiers
            .filter { currentValue >= $0.threshold }
            .map(\.tier)
            .max()
    }

    private static func currentValue(for metric: MilestoneMetric, state: MilestoneState) -> Double? {
        switch metric {
        case .strengthRatio(let exerciseKey):
            guard let bodyweightKg = state.bodyweightKg, bodyweightKg > 0,
                  let e1rm = state.bestE1RM[exerciseKey] else { return nil }
            return e1rm / bodyweightKg
        case .workoutCount:
            return Double(state.workoutCount)
        case .streakWeeks:
            return Double(state.streakWeeks)
        case .lifetimeTonnageKg:
            return state.lifetimeTonnageKg
        case .consistencyWeeks:
            return Double(state.consistentWeeks)
        }
    }

    private static func line(
        for definition: MilestoneDefinition, tier: Tier, state: MilestoneState
    ) -> String {
        switch definition.metric {
        case .strengthRatio(let exerciseKey):
            let e1rm = state.bestE1RM[exerciseKey] ?? 0
            let bodyweightKg = state.bodyweightKg ?? 0
            return "\(tier.displayName) · e1RM \(WeightFormat.kg(e1rm)) kg with bodyweight "
                + "\(WeightFormat.kg(bodyweightKg)) kg"
        case .workoutCount:
            return "\(tier.displayName) · \(state.workoutCount) workouts logged"
        case .streakWeeks:
            return "\(tier.displayName) · \(state.streakWeeks)-week streak"
        case .lifetimeTonnageKg:
            return "\(tier.displayName) · \(WeightFormat.kg(state.lifetimeTonnageKg)) kg lifted lifetime"
        case .consistencyWeeks:
            return "\(tier.displayName) · \(state.consistentWeeks) weeks hitting your goal"
        }
    }
}
