import Foundation

/// One set as logged in a past session, for progression purposes. Distinct
/// from `PersonalRecords.PerformedSet`: progression also needs the effort
/// rating (RPE), since several rules key off it.
public struct HistorySet: Hashable, Sendable {
    public var kind: SetKind
    public var weightKg: Double
    public var reps: Int
    public var effort: Effort?
    public var durationSeconds: Int?
    public var assistanceKg: Double?

    public init(
        kind: SetKind,
        weightKg: Double,
        reps: Int,
        effort: Effort? = nil,
        durationSeconds: Int? = nil,
        assistanceKg: Double? = nil
    ) {
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.effort = effort
        self.durationSeconds = durationSeconds
        self.assistanceKg = assistanceKg
    }
}

/// One past session's sets for a single routine exercise.
public struct ExerciseHistoryEntry: Hashable, Sendable {
    public var date: Date
    public var sets: [HistorySet]
    /// True when this session was a planned deload. Planned deloads are
    /// excluded from the baseline future progression builds from (plan.md §6.5).
    public var wasPlannedDeload: Bool

    public init(date: Date, sets: [HistorySet], wasPlannedDeload: Bool = false) {
        self.date = date
        self.sets = sets
        self.wasPlannedDeload = wasPlannedDeload
    }

    /// The working sets that count toward progression (warm-ups never do).
    public var workingSets: [HistorySet] {
        sets.filter { $0.kind.countsTowardStats }
    }
}

/// Persisted per routine-exercise: the engine's own memory between sessions.
/// `consecutiveMisses` is how many sessions in a row have missed their target
/// at `lastWeightKg`; a weight change resets it to 0 (plan.md §7). The other
/// fields are the per-rule state the review added — callers that persist this
/// as JSON must round-trip every field (`Codable` is provided for that).
public struct StallState: Hashable, Codable, Sendable {
    public var consecutiveMisses: Int
    public var lastWeightKg: Double?
    /// Double progression: the weakest set's reps last session at `lastWeightKg`,
    /// so "no improvement" can be detected.
    public var lastWeakestReps: Int?
    /// Timed rule: the hold the lifter was actually asked for last session — the
    /// number a miss is judged against, since the routine's target never moves.
    public var lastTargetSeconds: Int?
    /// Percent/TM rule: the `cycleIndex` the training max was last bumped in, so a
    /// bump happens once per cycle rather than on every week-1 call.
    public var trainingMaxCycle: Int?

    public init(
        consecutiveMisses: Int = 0, lastWeightKg: Double? = nil, lastWeakestReps: Int? = nil,
        lastTargetSeconds: Int? = nil, trainingMaxCycle: Int? = nil
    ) {
        self.consecutiveMisses = consecutiveMisses
        self.lastWeightKg = lastWeightKg
        self.lastWeakestReps = lastWeakestReps
        self.lastTargetSeconds = lastTargetSeconds
        self.trainingMaxCycle = trainingMaxCycle
    }

    /// Two stored weights are "the same" within a display round-trip (lb → kg → lb).
    public static func sameWeight(_ lhs: Double?, _ rhs: Double?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs - rhs) < 0.01
    }
}
