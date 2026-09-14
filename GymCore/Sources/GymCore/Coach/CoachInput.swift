import Foundation

/// One past session's plan-vs-actual, for the session-drift rule. The app layer builds this from
/// the routine's planned sets and the logged workout — `CoachEngine` never touches SwiftData.
public struct CoachSessionSummary: Hashable, Sendable {
    public var date: Date
    public var plannedSetCount: Int
    public var completedSetCount: Int
    public var durationSeconds: Int

    public init(date: Date, plannedSetCount: Int, completedSetCount: Int, durationSeconds: Int) {
        self.date = date
        self.plannedSetCount = plannedSetCount
        self.completedSetCount = completedSetCount
        self.durationSeconds = durationSeconds
    }
}

/// One lift's recent picture, gathering exactly what the stalled-lift, e1RM-downtrend and
/// deload-overdue rules need — reusing `StallState` (already persisted by the progression engine)
/// and the same `e1rmTrend`/`rpeAtSameLoadTrend` shape `DeloadDetector.LiftSnapshot` takes, so the
/// app layer assembles this once and both engines read from it.
public struct CoachLiftSnapshot: Hashable, Sendable {
    public var name: String
    public var stallState: StallState
    /// e1RM from recent sessions, oldest first, excluding planned deloads — same contract as
    /// `DeloadDetector.LiftSnapshot.e1rmTrend`.
    public var e1rmTrend: [Double]
    public var rpeAtSameLoadTrend: [Double]?
    public var lastWorkingWeightKg: Double?
    public var lastWorkingSetCount: Int?
    /// Sessions in a row this lift was either missed (target not hit) or logged as a failure —
    /// the struggling-exercise rule's own counter, distinct from `stallState.consecutiveMisses`
    /// (which only tracks "same weight, no progress", not failed/skipped sets).
    public var consecutiveFailedSessions: Int
    /// This lift's own muscle/equipment identity, for `Substitutions.candidates` — nil when the
    /// app hasn't resolved a library entry for it (the struggling-exercise rule then stays quiet
    /// for this lift rather than guessing).
    public var substitutionCandidate: SubstitutionCandidate?

    public init(
        name: String, stallState: StallState, e1rmTrend: [Double], rpeAtSameLoadTrend: [Double]? = nil,
        lastWorkingWeightKg: Double? = nil, lastWorkingSetCount: Int? = nil,
        consecutiveFailedSessions: Int = 0, substitutionCandidate: SubstitutionCandidate? = nil
    ) {
        self.name = name
        self.stallState = stallState
        self.e1rmTrend = e1rmTrend
        self.rpeAtSameLoadTrend = rpeAtSameLoadTrend
        self.lastWorkingWeightKg = lastWorkingWeightKg
        self.lastWorkingSetCount = lastWorkingSetCount
        self.consecutiveFailedSessions = consecutiveFailedSessions
        self.substitutionCandidate = substitutionCandidate
    }

    /// The `DeloadDetector.LiftSnapshot` view of this lift, for the deload-overdue rule.
    var deloadSnapshot: LiftSnapshot {
        LiftSnapshot(
            name: name, stalls: stallState.consecutiveMisses, e1rmTrend: e1rmTrend,
            rpeAtSameLoadTrend: rpeAtSameLoadTrend
        )
    }
}

/// A PR earned recently, paired with the exercise name (`PersonalRecord` itself doesn't carry
/// one) — for the PR/milestone rule.
public struct CoachPersonalRecordHighlight: Hashable, Sendable {
    public var exerciseName: String
    public var record: PersonalRecord

    public init(exerciseName: String, record: PersonalRecord) {
        self.exerciseName = exerciseName
        self.record = record
    }
}

/// A milestone tier earned recently, paired with the date it was earned (`Achievement` itself
/// doesn't carry one — `Milestones.evaluate` is a point-in-time call, so the app records when).
public struct CoachAchievementHighlight: Hashable, Sendable {
    public var achievement: Achievement
    public var date: Date

    public init(achievement: Achievement, date: Date) {
        self.achievement = achievement
        self.date = date
    }
}

/// One past approval or dismissal, keyed by the same `(rule, fingerprint)` pair `CoachCard`
/// computes — the engine's only persisted state. The app layer stores and replays this list; the
/// engine itself never writes anything.
public struct CoachInteraction: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable { case dismissed, approved }

    public var rule: CoachRule
    public var fingerprint: String
    public var outcome: Outcome
    public var date: Date

    public init(rule: CoachRule, fingerprint: String, outcome: Outcome, date: Date) {
        self.rule = rule
        self.fingerprint = fingerprint
        self.outcome = outcome
        self.date = date
    }
}

/// Everything `CoachEngine.cards(for:now:calendar:)` needs, assembled by the app layer from
/// SwiftData. Each field is already the shape some existing GymCore engine consumes or produces
/// (`WeeklySchedule`, `StallState`, `Recovery.map`, `Milestones`/`PersonalRecords`) — `CoachInput`
/// doesn't re-derive any of that, it just collects it for the ten rules to read.
public struct CoachInput: Sendable {
    // Adherence
    public var schedule: WeeklySchedule
    public var workoutDates: [Date]

    // Session drift
    public var recentSessions: [CoachSessionSummary]

    // Muscle coverage: sets per muscle over the rolling `coachCoverageWindowDays` window, already
    // computed (e.g. via `BodySeries.setsPerMuscle(workouts:window:now:calendar:)`).
    public var muscleSetsInWindow: [Muscle: Double]
    public var trackedMuscles: [Muscle]

    // Per-lift state: stalls, e1RM trend, struggling/substitution info.
    public var lifts: [CoachLiftSnapshot]

    // Deload overdue: consecutive hard calendar weeks, for `DeloadDetector.evaluate`.
    public var hardWeeksInARow: Int

    // Struggling exercise → substitution.
    public var substitutionLibrary: [SubstitutionCandidate]
    public var availableEquipment: Set<String>

    // Recovery debt: `Recovery.map`'s 0 (fresh) … 1 (spent) output.
    public var recoveryMap: [Muscle: Double]

    // PR / milestone highlights.
    public var recentPRs: [CoachPersonalRecordHighlight]
    public var recentAchievements: [CoachAchievementHighlight]

    // Long layoff.
    public var lastWorkoutDate: Date?

    // Dismissal/cooldown state.
    public var interactions: [CoachInteraction]

    public init(
        schedule: WeeklySchedule = WeeklySchedule(),
        workoutDates: [Date] = [],
        recentSessions: [CoachSessionSummary] = [],
        muscleSetsInWindow: [Muscle: Double] = [:],
        // Empty, not `Muscle.allCases`: an app layer that hasn't computed a coverage window yet
        // (or a truly empty `CoachInput()`) must not have every muscle read as an untouched gap.
        trackedMuscles: [Muscle] = [],
        lifts: [CoachLiftSnapshot] = [],
        hardWeeksInARow: Int = 0,
        substitutionLibrary: [SubstitutionCandidate] = [],
        availableEquipment: Set<String> = [],
        recoveryMap: [Muscle: Double] = [:],
        recentPRs: [CoachPersonalRecordHighlight] = [],
        recentAchievements: [CoachAchievementHighlight] = [],
        lastWorkoutDate: Date? = nil,
        interactions: [CoachInteraction] = []
    ) {
        self.schedule = schedule
        self.workoutDates = workoutDates
        self.recentSessions = recentSessions
        self.muscleSetsInWindow = muscleSetsInWindow
        self.trackedMuscles = trackedMuscles
        self.lifts = lifts
        self.hardWeeksInARow = hardWeeksInARow
        self.substitutionLibrary = substitutionLibrary
        self.availableEquipment = availableEquipment
        self.recoveryMap = recoveryMap
        self.recentPRs = recentPRs
        self.recentAchievements = recentAchievements
        self.lastWorkoutDate = lastWorkoutDate
        self.interactions = interactions
    }
}
