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
}
