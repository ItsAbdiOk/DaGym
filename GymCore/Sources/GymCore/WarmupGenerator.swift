import Foundation

/// One generated warm-up set.
public struct WarmupSet: Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int

    public init(weightKg: Double, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// How weight is loaded, which decides the ramp and the rounding grid.
///
/// This is a property of how the set is *logged*, not of the kit it happens on: an assisted
/// pull-up done on a "machine" logs assistance, and a plank done with a "barbell" logs seconds.
/// Deciding from the equipment name alone is what produced warm-ups heavier than the working
/// set. See `ExerciseInfo.warmupLoadingStyle`.
public enum LoadingStyle: Equatable, Sendable {
    case barbell(bar: Bar)
    case dumbbell
    case machine
    case bodyweight
    /// The logged number is assistance, so a 40 %/60 %/80 % ramp *removes* help and makes every
    /// "warm-up" harder than the working set. There is no sensible ramp: none are generated.
    case assisted
    /// Timed holds and cardio: the working number is seconds, not load, so a rep-based ramp is
    /// meaningless. None are generated.
    case timed
}

/// Ramp-up sets toward the first working set. Warm-ups never count toward
/// 1RM, progression, PRs or fatigue.
public enum WarmupGenerator {
    /// - Parameters:
    ///   - workingWeightKg: weight of the first working set.
    ///   - estimatedOneRepMax: when known, a 90 % single is added for heavy days.
    ///   - increment: smallest loadable step, used only when `grid` is nil.
    ///   - grid: the equipment's own grid. Supply it and every warm-up comes back on a weight
    ///     this gym can actually load — rounding to a bare increment happily asks for 42.5 kg
    ///     from a rack with no 1.25 s.
    public static func sets(
        workingWeightKg: Double,
        style: LoadingStyle,
        estimatedOneRepMax: Double? = nil,
        increment: Double = 2.5,
        grid: LoadGrid? = nil
    ) -> [WarmupSet] {
        let grid = grid ?? .step(increment)
        switch style {
        case .bodyweight, .assisted, .timed:
            return []
        case .dumbbell, .machine:
            return ramp(
                scheme: TrainingConstants.dumbbellWarmupScheme,
                working: workingWeightKg, floor: 0, grid: grid
            )
        case .barbell(let bar):
            var scheme = TrainingConstants.barbellWarmupScheme
            if let e1rm = estimatedOneRepMax, e1rm > 0,
               workingWeightKg / e1rm >= TrainingConstants.heavySingleThreshold {
                scheme.append((TrainingConstants.heavySingleFraction, 1))
            }
            var result: [WarmupSet] = []
            if workingWeightKg > bar.weightKg + 0.001 {
                let reps = TrainingConstants.emptyBarWarmupReps
                result.append(WarmupSet(weightKg: bar.weightKg, reps: reps))
            }
            result += ramp(
                scheme: scheme, working: workingWeightKg, floor: bar.weightKg, grid: grid
            )
            return result
        }
    }

    /// Rounds each step onto the grid; drops steps that are not heavier than the
    /// previous one or the floor, or that reach the working weight.
    private static func ramp(
        scheme: [(fraction: Double, reps: Int)],
        working: Double,
        floor: Double,
        grid: LoadGrid
    ) -> [WarmupSet] {
        var result: [WarmupSet] = []
        var last = floor
        for step in scheme {
            let weight = grid.nearest(working * step.fraction)
            guard weight > last + 0.001, weight < working - 0.001 else { continue }
            result.append(WarmupSet(weightKg: weight, reps: step.reps))
            last = weight
        }
        return result
    }

    static func round(_ value: Double, to increment: Double) -> Double {
        LoadGrid.step(increment).nearest(value)
    }
}
