import Foundation

/// Every tunable number in the training engine lives here so it can be
/// adjusted in one place.
public enum TrainingConstants {
    /// Sets with more reps than this are too far from a max to estimate one.
    public static let maxRepsForOneRepMax = 12

    /// Default warm-up ramp for barbell lifts: (fraction of working weight, reps).
    public static let barbellWarmupScheme: [(fraction: Double, reps: Int)] = [
        (0.40, 5), (0.60, 3), (0.80, 2)
    ]
    /// Extra single at 90 % when the working weight is at least this share of e1RM.
    public static let heavySingleThreshold = 0.85
    public static let heavySingleFraction = 0.90
    public static let emptyBarWarmupReps = 10

    /// Default warm-up ramp for dumbbell and machine work.
    public static let dumbbellWarmupScheme: [(fraction: Double, reps: Int)] = [
        (0.50, 8), (0.75, 4)
    ]

    /// §7 recovery model. A muscle above this "spent" score (0…1) is called out by name in the
    /// recovery headline; below it, it's lumped in with the "fresh" muscles.
    public static let recoveryHeadlineThreshold = 0.3
    /// §7 recovery model: raw fatigue (Σ effort × share, decayed) is divided by this before the
    /// saturating curve, so ~one hard session's worth of primary sets (6 at RIR 0) reads 50 % spent.
    /// Without it a single hard set already read 50 % and a 10-set day stayed "spent" for 4 days.
    /// This is the *only* normalisation in the model, and it is the same constant for every
    /// lifter — the map reads absolute recent work, not work relative to the lifter's habits.
    public static let recoveryFatigueScale = 6.0

    // MARK: - Progression

    /// The heaviest load any single set may carry, whatever the source — a spoken number, an
    /// imported CSV cell, a shared plan's target. The heaviest anything lifted in competition is
    /// a ~500 kg deadlift; a leg-press sled with every plate in the gym is around here. Above
    /// it the value is a mishearing or a corrupt cell, not a set, and every validator rejects it
    /// rather than storing it. Voice, import and plan sanitising all read this one number.
    public static let maxLoadKg = 600.0

    /// Default per-set weight increments when an exercise doesn't override them.
    public static let defaultUpperBodyIncrementKg = 2.5
    public static let defaultLowerBodyIncrementKg = 5.0

    /// Linear rule: consecutive misses at the same weight before a deload is triggered.
    public static let linearMissesBeforeDeload = 3
    /// Linear rule: deload target as a fraction of the stalled working weight (SS/SL-style 10 %),
    /// also applied to e1RM as a cap. Always at least one increment below the stalled weight.
    public static let linearDeloadFraction = 0.90

    /// Double progression: sessions in a row with no rep improvement at the same weight before
    /// dropping one increment and asking for the top of the range again.
    public static let doubleProgressionMissesBeforeDeload = 3

    /// The step non-barbell loads fall back to when no `LoadGrid` is supplied and the target is
    /// lighter than the bar (a 12 kg dumbbell can't be "rounded onto" a 20 kg bar).
    public static let defaultStepKg = 2.5

    /// The most any rule may add in one session as a fraction of the previous load; explicit
    /// deloads are exempt. A grid step may still exceed it — a 12 kg dumbbell has nothing
    /// between it and 14 — but only within `maxGridStepIncrements`; a coarser rung is a hold.
    public static let maxSessionIncreaseFraction = 0.10

    /// How many of the rule's own increments the next loadable rung may be past the current
    /// load before the engine holds rather than prescribes it (`RuleContext.oversizedRung`).
    /// The fraction alone can't draw this line: 6 → 8 kg dumbbells (+33 %) is an ordinary step
    /// and must stay allowed, while 40 → 70 kg on a rack of 25s and 10s (+75 %) is what the cap
    /// exists to stop. Measured against the increment, a 2 kg dumbbell step is under one
    /// increment and the 30 kg rung is twelve; a rack of 20s and 10s at 60 kg (→ 80, eight
    /// increments) holds too. Two increments (an empty bar with only 2.5 kg plates, 20 → 25) and
    /// an AMRAP double-increment session both fall inside the line.
    public static let maxGridStepIncrements = 4.0

    /// RPE-based rule: the most the load may move in one session, as a fraction of the previous
    /// load, whatever the raw e1RM arithmetic says (a single "@5 → @10" pair allows +14 %).
    public static let rpeMaxSessionChangeFraction = 0.10

    /// Linear + AMRAP rule: AMRAP reps at or above this multiple of the target doubles the
    /// increment; below target reps, the weight is reset by `amrapMissFraction`.
    public static let amrapDoubleIncrementMultiple = 2.0
    public static let amrapMissFraction = 0.90
    /// Linear + AMRAP rule: consecutive AMRAP misses before the 10 % back-off (one bad AMRAP with
    /// normal noise is a repeat, not a reset).
    public static let amrapMissesBeforeReset = 2

    /// Bodyweight rule: reps climb to this ceiling before a set is added, up to `maxSets`.
    public static let bodyweightRepCeiling = 15
    public static let bodyweightMaxSets = 5

    /// Assisted rule: assistance never drops below this floor.
    public static let assistedFloorKg = 0.0
    public static let defaultAssistedStepKg = 2.5

    /// Timed rule: default seconds added when every hold is hit, and the hold length past which
    /// the rule stops adding time and suggests load / a harder variation instead.
    public static let defaultTimedStepSeconds = 5
    public static let timedCeilingSeconds = 120
    /// Timed rule: after `linearMissesBeforeDeload` short holds in a row, back the hold off to
    /// this fraction of what was asked, rounded down to `timedRoundingSeconds`.
    public static let timedBackoffFraction = 0.90
    public static let timedRoundingSeconds = 5

    /// Percent/training-max rule: TM as a fraction of e1RM when none is set yet, and the
    /// per-cycle bump applied after week 4.
    public static let trainingMaxFraction = 0.90
    public static let trainingMaxUpperIncrementKg = 2.5
    public static let trainingMaxLowerIncrementKg = 5.0

    /// The 5/3/1-style 4-week wave: week → [(percent of TM, reps, isAMRAP)].
    public static let waveScheme: [Int: [(percent: Double, reps: Int, isAMRAP: Bool)]] = [
        1: [(0.65, 5, false), (0.75, 5, false), (0.85, 5, true)],
        2: [(0.70, 3, false), (0.80, 3, false), (0.90, 3, true)],
        3: [(0.75, 5, false), (0.85, 3, false), (0.95, 1, true)],
        4: [(0.40, 5, false), (0.50, 5, false), (0.60, 5, false)]
    ]

    /// Deload detection thresholds (plan.md §7).
    ///
    /// `DeloadDetector` is fed `StallState.consecutiveMisses` as the engine judges it *now* —
    /// `WorkoutStore+Coach.swift` re-runs the engine over current history so the newest logged
    /// session is counted (the persisted copy lags one session; see `coachStalledLiftMisses`).
    /// Even so the number cannot reach `linearMissesBeforeDeload`: every rule that counts misses
    /// zeroes the counter on the miss that trips its own deload, so the reachable values are
    /// {0, 1, 2} for linear, double progression and timed, {0, 1} for linear + AMRAP
    /// (`amrapMissesBeforeReset` is 2), and always 0 for RPE / training-max / bodyweight /
    /// assisted, which never increment it at all.
    ///
    /// 3 was consequently dead: no lift ever reached it, so the stall arm of
    /// `DeloadDetector.stallReasons` — and `CoachLiftSnapshot.drivesDeloadSuggestion`, which
    /// shares this constant — could never fire. 2 is the top of the reachable range and means
    /// what a deload suggestion should mean: two sessions in a row judged short at the same
    /// weight, one more miss from the engine's own deload. Requiring `deloadMinLiftsStalling` of
    /// them keeps it a programme-wide signal rather than one bad lift.
    public static let deloadStallCount = 2
    /// How many recent sessions `LiftSnapshot.e1rmTrend`/`rpeAtSameLoadTrend` carry for
    /// `DeloadDetector` — its regression check compares the last three points, and its
    /// `isNotProgressing` check compares the first against the last, so a longer array
    /// silently turns "lower than four months ago" into "not progressing".
    public static let deloadTrendSessions = 3
    public static let deloadMinLiftsStalling = 2
    public static let deloadE1rmDropFraction = 0.05
    public static let deloadRpeRiseThreshold = 1.0
    public static let deloadHardWeeksThreshold = 5

    /// Deload plan: fraction of normal sets and load to prescribe.
    public static let deloadSetsFraction = 0.6
    public static let deloadLoadFraction = 0.9
}

// MARK: - Recovery attribution, retention and balance (OpenGym parity, insights recs 2–4)

extension TrainingConstants {
    /// §7 recovery model: two stimulus events on the same muscle further apart than this are
    /// treated as separate sessions in the per-session breakdown.
    public static let recoverySessionGapHours = 6.0

    /// §7 recovery model: how much of a set a drop or rest-pause chunk counts as. It continues
    /// the set before it at a lower load (or after a few seconds), so a triple-drop is one set
    /// plus two halves, not three sets. See `StimulusAttribution`.
    public static let recoveryContinuationSetWeight = 0.5
    /// §7 recovery model: effort assumed for a working set the lifter never rated — between
    /// RIR 0 (1.0) and RIR ≥ 4 (0.5). `.failure`/`.amrap` sets don't use it: their kind already
    /// says they were maximal.
    public static let recoveryUnratedEffort = 0.75

    /// Strength retention: full (1.0) for this many days after a muscle's last counting set…
    public static let retentionFullDays = 14.0
    /// …then halves every this many days…
    public static let retentionHalfLifeDays = 28.0
    /// …down to this floor, which is also where a never-trained muscle sits.
    public static let retentionFloor = 0.5

    /// Balance map "hard sets only": a set counts as hard at this RIR or fewer (or when its kind
    /// is `.failure`/`.amrap`).
    public static let hardSetMaxRIR = 1
}

// MARK: - Coach (rule-based, deterministic coaching cards)

extension TrainingConstants {
    /// The most cards `CoachEngine` returns in one call — a brand-new lifter with a handful of
    /// workouts must not be buried even if several rules technically fire.
    public static let coachMaxCards = 5

    /// Adherence: complete calendar weeks (most recent first, excluding the in-progress week)
    /// compared against the schedule.
    public static let coachAdherenceLookbackWeeks = 4
    /// Adherence: the two most recent weeks' completion rate vs. the two before that must drop by
    /// at least this fraction to fire — noise from a single light week isn't "dropping".
    public static let coachAdherenceDropFraction = 0.34
    public static let coachAdherenceCooldownDays = 5

    /// Session drift: sessions compared (most recent) against the baseline window just before them.
    public static let coachDriftRecentSessions = 4
    public static let coachDriftBaselineSessions = 8
    /// Session drift: a drop of this fraction in either completed/planned-set ratio or average
    /// session duration counts as drift.
    public static let coachDriftDropFraction = 0.25
    public static let coachDriftCooldownDays = 5
    /// Session drift: a logged session longer than this is a workout someone forgot to finish,
    /// not a long session. It carries no usable duration signal, so it's left out of both the
    /// recent and the baseline average rather than inflating the baseline it's compared against.
    public static let coachDriftMaxSessionSeconds = 4 * 3600

    /// Muscle coverage: the rolling window the caller's sets-per-muscle map already covers, and
    /// the floor below which a muscle counts as a coverage gap.
    public static let coachCoverageWindowDays = 14
    /// Counted the way `BodySeries.setsPerMuscle` counts: a primary mover is 1, a secondary
    /// mover 0.5. Only muscles some routine trains *as a primary mover* are checked against it
    /// (see `CoachInput.trackedMuscles`), so this is a floor on real direct work — 4 sets in 14
    /// days is roughly "trained once a fortnight", not a training recommendation.
    public static let coachMinSetsPerMuscleInWindow = 4.0
    public static let coachCoverageCooldownDays = 7
    /// Muscle coverage: at most this many gap muscles are named in one card.
    public static let coachCoverageMaxNamedMuscles = 3

    /// Stalled lift: the `StallState.consecutiveMisses` at which the per-lift card fires — two
    /// sessions in a row missed at the same weight, one short of `linearMissesBeforeDeload`, so
    /// the card lands while the engine is still offering "repeat the same weight" and says
    /// something the app hasn't yet.
    ///
    /// The number is only honest against an **un-lagged** stall state. `WorkoutStore.finish`
    /// commits the stall that `startWorkout` computed for the session being finished, so the
    /// *persisted* counter is always one session behind: persisted `n` means `n` judged misses
    /// plus one logged session not yet judged — which may have been a hit. Reading the persisted
    /// value here (as this once did, at 1, with a `+ 1` in the copy) carded a lift after one
    /// miss and one clean hit, while the engine's next prescription was an increase, and the
    /// approved deload then overrode that increase. `CoachLiftSnapshot.stallState` is therefore
    /// built by re-running the engine over current history (`WorkoutStore+Coach.swift`), which
    /// judges the newest session too; the same snapshot feeds `DeloadDetector`, whose
    /// `deloadStallCount` is read on the same footing.
    ///
    /// (Values of 3 and above do still occur, but only via `RuleContext.lightestLoadPrescribed`
    /// — a lift with nothing lighter on the equipment, which the card handles with no weight to
    /// suggest.)
    public static let coachStalledLiftMisses = 2
    public static let coachStalledLiftCooldownDays = 7

    /// e1RM downtrend: the trailing session count the trend is judged over, and how far the most
    /// recent e1RM must sit below the window's peak.
    public static let coachE1rmDowntrendSessions = 4
    public static let coachE1rmDowntrendFraction = 0.05
    public static let coachE1rmDowntrendCooldownDays = 7

    /// Deload overdue: `DeloadDetector.evaluate` already carries its own thresholds — this is
    /// just how long a dismissed/approved suggestion stays quiet.
    public static let coachDeloadCooldownDays = 10

    /// Struggling exercise: consecutive sessions that came up short of the lift's own rep target
    /// before a substitution is offered. Strictly above `linearMissesBeforeDeload` so the
    /// progression engine's own deload gets a full run at the problem first — telling someone to
    /// abandon a lift before it has even been repeated at a lighter weight is premature.
    public static let coachStrugglingConsecutiveFailures = 4
    public static let coachSubstitutionCooldownDays = 7

    /// Recovery debt: a muscle at or above this "spent" score (`Recovery.map` scale, 0…1) counts
    /// toward the debt; at least this many such muscles at once fires the card.
    ///
    /// `Recovery.map` is `f / (recoveryFatigueScale + f)` in raw fatigue `f`, and one hard
    /// session's worth of primary sets is `f == recoveryFatigueScale` (0.5). The old 0.75 needed
    /// `f == 3 × recoveryFatigueScale` — three undecayed hard sessions on the same muscle, which
    /// a lifter training it twice a week never reaches. 0.6 is `f == 1.5 ×`: one hard session
    /// plus part of another still in the window.
    public static let coachRecoveryDebtThreshold = 0.6
    public static let coachRecoveryDebtMinMuscles = 2
    public static let coachRecoveryDebtCooldownDays = 3
    /// Recovery debt: logged sessions required before the rule is allowed to fire at all. Not a
    /// correction for the fatigue math (which is absolute and meaningful from the first set) —
    /// a rate limit on the advice: "you've trained these hard recently" off one or two logged
    /// sessions is a guess about a lifter the app has barely seen.
    public static let coachRecoveryDebtMinSessions = 6

    /// PR / milestone: how recent an achievement or PR must be to still be worth a card. The
    /// cooldown must outlast the lookback, or a dismissed PR card comes back tomorrow and the day
    /// after — the same PR is not new evidence.
    public static let coachHighlightLookbackDays = 3.0
    public static let coachHighlightCooldownDays = 4
    /// A dismissed or approved review proposal stays quiet for two weeks — the review is
    /// on-demand, and re-proposing the same change every tap would make "Dismiss" meaningless.
    public static let coachReviewCooldownDays = 14

    /// Long layoff: days since the last logged workout before a "return to training" card fires.
    public static let coachLayoffMinDays = 10
    public static let coachLayoffCooldownDays = 14
    /// Long layoff: the working weight fraction suggested for the first session back.
    public static let coachLayoffEaseBackFraction = 0.8
}
