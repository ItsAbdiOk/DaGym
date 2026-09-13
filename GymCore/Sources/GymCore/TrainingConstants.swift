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
    public static let recoveryFatigueScale = 6.0

    // MARK: - Progression

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

    /// The most any rule may add in one session as a fraction of the previous load (a plate
    /// grid can still force one grid step); explicit deloads are exempt.
    public static let maxSessionIncreaseFraction = 0.10

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

    /// Percent/training-max rule: TM as a fraction of e1RM when none is set yet, and the
    /// per-cycle bump applied after week 4.
    public static let trainingMaxFraction = 0.90
    public static let trainingMaxUpperIncrementKg = 2.5
    public static let trainingMaxLowerIncrementKg = 5.0

    // swiftlint:disable large_tuple
    /// The 5/3/1-style 4-week wave: week → [(percent of TM, reps, isAMRAP)].
    public static let waveScheme: [Int: [(percent: Double, reps: Int, isAMRAP: Bool)]] = [
        1: [(0.65, 5, false), (0.75, 5, false), (0.85, 5, true)],
        2: [(0.70, 3, false), (0.80, 3, false), (0.90, 3, true)],
        3: [(0.75, 5, false), (0.85, 3, false), (0.95, 1, true)],
        4: [(0.40, 5, false), (0.50, 5, false), (0.60, 5, false)]
    ]
    // swiftlint:enable large_tuple

    /// Deload detection thresholds (plan.md §7).
    public static let deloadStallCount = 3
    public static let deloadMinLiftsStalling = 2
    public static let deloadE1rmDropFraction = 0.05
    public static let deloadRpeRiseThreshold = 1.0
    public static let deloadHardWeeksThreshold = 5

    /// Deload plan: fraction of normal sets and load to prescribe.
    public static let deloadSetsFraction = 0.6
    public static let deloadLoadFraction = 0.9
}
