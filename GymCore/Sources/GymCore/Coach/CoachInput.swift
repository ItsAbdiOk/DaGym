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
    /// The library exercise this lift is, so an approved action names a row rather than a string
    /// (two custom exercises may share a name). Nil when the app layer couldn't resolve one.
    public var exerciseID: UUID?
    public var stallState: StallState
    /// e1RM from recent sessions, oldest first, excluding planned deloads, at most
    /// `TrainingConstants.coachE1rmDowntrendSessions` long — the window this coach's own
    /// downtrend rule judges. Longer is not better: `deloadSnapshot` trims it again to the three
    /// points `DeloadDetector.LiftSnapshot.e1rmTrend` is specified over.
    public var e1rmTrend: [Double]
    /// Average RPE at the same load, oldest first, same length contract as `e1rmTrend`.
    public var rpeAtSameLoadTrend: [Double]?
    /// The rounding grid this lift's load must land on (plates, a dumbbell step, a machine
    /// stack). Nil for bodyweight/assisted/timed work and when the app layer can't tell — the
    /// stalled-lift rule then names no concrete weight rather than inventing an unloadable one.
    public var loadGrid: LoadGrid?
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
    /// The miss streak at which this lift counts as stalled for the stalled-lift card and the
    /// deload detector: `TrainingConstants.coachStalledLiftMisses`, capped one short of the
    /// lift's own rule's reset (`ProgressionRule.missesBeforeReset`). Linear + AMRAP zeroes its
    /// counter on the second miss, so against the flat constant its streak of {0, 1} could never
    /// count as stalled and the card silently stopped firing for that rule.
    public var stalledLiftMisses: Int

    public init(
        name: String, exerciseID: UUID? = nil, stallState: StallState, e1rmTrend: [Double],
        rpeAtSameLoadTrend: [Double]? = nil, loadGrid: LoadGrid? = nil,
        lastWorkingWeightKg: Double? = nil, lastWorkingSetCount: Int? = nil,
        consecutiveFailedSessions: Int = 0, substitutionCandidate: SubstitutionCandidate? = nil,
        stalledLiftMisses: Int = TrainingConstants.coachStalledLiftMisses
    ) {
        self.stalledLiftMisses = stalledLiftMisses
        self.name = name
        self.exerciseID = exerciseID
        self.stallState = stallState
        self.e1rmTrend = e1rmTrend
        self.rpeAtSameLoadTrend = rpeAtSameLoadTrend
        self.loadGrid = loadGrid
        self.lastWorkingWeightKg = lastWorkingWeightKg
        self.lastWorkingSetCount = lastWorkingSetCount
        self.consecutiveFailedSessions = consecutiveFailedSessions
        self.substitutionCandidate = substitutionCandidate
    }

    /// The `DeloadDetector.LiftSnapshot` view of this lift, for the deload-overdue rule. Both
    /// trends are trimmed to the last `TrainingConstants.deloadTrendSessions` points that type is
    /// specified over: `DeloadDetector.isNotProgressing` compares the *first* element against the
    /// last, so handing it a longer history would read "higher than a season ago" as "not
    /// progressing" for anyone who has ever had a better month.
    /// `stalledLiftMisses(for:)` — the threshold a rule's own reset allows.
    public static func stalledLiftMisses(for rule: ProgressionRule?) -> Int {
        let base = TrainingConstants.coachStalledLiftMisses
        guard let reset = rule?.missesBeforeReset else { return base }
        return max(1, min(base, reset - 1))
    }

    /// Sessions in a row judged short at the same weight, against this lift's own threshold.
    public var isStalled: Bool { stallState.consecutiveMisses >= stalledLiftMisses }

    var deloadSnapshot: LiftSnapshot {
        let window = TrainingConstants.deloadTrendSessions
        return LiftSnapshot(
            name: name, stalls: stallState.consecutiveMisses, stallThreshold: stalledLiftMisses,
            e1rmTrend: Array(e1rmTrend.suffix(window)),
            rpeAtSameLoadTrend: rpeAtSameLoadTrend.map { Array($0.suffix(window)) }
        )
    }

    /// True when this lift alone is enough for `DeloadDetector` to say something — used to
    /// collapse the deload-overdue card into the per-lift card that already covers the same
    /// evidence. The stall arm is checked directly because `DeloadDetector` only reports stalls
    /// once `deloadMinLiftsStalling` lifts share one.
    var drivesDeloadSuggestion: Bool {
        if isStalled { return true }
        return DeloadDetector.evaluate(lifts: [deloadSnapshot], hardWeeks: 0) != nil
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
    /// The dates of sessions **logged in DaGym**, for the adherence rule only — Apple Health
    /// imports are deliberately excluded. A Health-imported run broke the rest day (so it
    /// belongs in `workoutDates`, which feeds `Streaks`), but it is not one of the planned gym
    /// sessions the lifter's schedule asked for, and counting it made a week of running read as
    /// perfect adherence to a lifting plan. Defaults to `workoutDates` when not supplied.
    public var loggedWorkoutDates: [Date]
    /// When `schedule` was last edited, if known. Weeks that began before this are not scored:
    /// the schedule holds only the *current* plan, so grading a week from a month ago against a
    /// plan written yesterday rewrote the lifter's own history every time they changed their
    /// mind about which days they train.
    public var scheduleUpdatedAt: Date?

    // Session drift
    public var recentSessions: [CoachSessionSummary]

    // Muscle coverage: sets per muscle over the rolling `coachCoverageWindowDays` window, already
    // computed (e.g. via `BodySeries.setsPerMuscle(workouts:window:now:calendar:)`).
    public var muscleSetsInWindow: [Muscle: Double]
    /// The muscles this lifter's *current* plan trains as a **primary** mover. Secondary-only
    /// muscles are deliberately excluded: `setsPerMuscle` weights a secondary mover at 0.5, so a
    /// muscle that only ever gets incidental work can never clear
    /// `coachMinSetsPerMuscleInWindow` and would flag a gap forever for training that is going
    /// exactly to plan.
    public var trackedMuscles: [Muscle]

    // Per-lift state: stalls, e1RM trend, struggling/substitution info.
    public var lifts: [CoachLiftSnapshot]

    // Deload overdue: consecutive hard calendar weeks, for `DeloadDetector.evaluate`.
    public var hardWeeksInARow: Int

    // Struggling exercise → substitution.
    public var substitutionLibrary: [SubstitutionCandidate]
    /// The active equipment profile: kinds, and the stations when it narrows to them.
    public var equipmentAvailability: EquipmentAvailability
    /// The ticked equipment kinds alone — `equipmentAvailability.types`.
    public var availableEquipment: Set<String> {
        get { equipmentAvailability.types }
        set { equipmentAvailability.types = newValue }
    }

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
        loggedWorkoutDates: [Date]? = nil,
        scheduleUpdatedAt: Date? = nil,
        recentSessions: [CoachSessionSummary] = [],
        muscleSetsInWindow: [Muscle: Double] = [:],
        // Empty, not `Muscle.allCases`: an app layer that hasn't computed a coverage window yet
        // (or a truly empty `CoachInput()`) must not have every muscle read as an untouched gap.
        trackedMuscles: [Muscle] = [],
        lifts: [CoachLiftSnapshot] = [],
        hardWeeksInARow: Int = 0,
        substitutionLibrary: [SubstitutionCandidate] = [],
        availableEquipment: Set<String> = [],
        equipmentAvailability: EquipmentAvailability? = nil,
        recoveryMap: [Muscle: Double] = [:],
        recentPRs: [CoachPersonalRecordHighlight] = [],
        recentAchievements: [CoachAchievementHighlight] = [],
        lastWorkoutDate: Date? = nil,
        interactions: [CoachInteraction] = []
    ) {
        self.schedule = schedule
        self.workoutDates = workoutDates
        self.loggedWorkoutDates = loggedWorkoutDates ?? workoutDates
        self.scheduleUpdatedAt = scheduleUpdatedAt
        self.recentSessions = recentSessions
        self.muscleSetsInWindow = muscleSetsInWindow
        self.trackedMuscles = trackedMuscles
        self.lifts = lifts
        self.hardWeeksInARow = hardWeeksInARow
        self.substitutionLibrary = substitutionLibrary
        self.equipmentAvailability = equipmentAvailability ?? EquipmentAvailability(types: availableEquipment)
        self.recoveryMap = recoveryMap
        self.recentPRs = recentPRs
        self.recentAchievements = recentAchievements
        self.lastWorkoutDate = lastWorkoutDate
        self.interactions = interactions
    }
}
