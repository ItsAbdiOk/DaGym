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
public enum LoadingStyle: Sendable {
    case barbell(bar: Bar)
    case dumbbell
    case machine
    case bodyweight
}

/// Ramp-up sets toward the first working set. Warm-ups never count toward
/// 1RM, progression, PRs or fatigue.
public enum WarmupGenerator {
    /// - Parameters:
    ///   - workingWeightKg: weight of the first working set.
    ///   - estimatedOneRepMax: when known, a 90 % single is added for heavy days.
    ///   - increment: smallest loadable step (e.g. 2.5 kg for a bar with 1.25 plates).
    public static func sets(
        workingWeightKg: Double,
        style: LoadingStyle,
        estimatedOneRepMax: Double? = nil,
        increment: Double = 2.5
    ) -> [WarmupSet] {
        switch style {
        case .bodyweight:
            return []
        case .dumbbell, .machine:
            return ramp(
                scheme: TrainingConstants.dumbbellWarmupScheme,
                working: workingWeightKg, floor: 0, increment: increment
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
                scheme: scheme, working: workingWeightKg, floor: bar.weightKg, increment: increment
            )
            return result
        }
    }

    /// Rounds each step to the grid; drops steps that are not heavier than the
    /// previous one or the floor, or that reach the working weight.
    private static func ramp(
        scheme: [(fraction: Double, reps: Int)],
        working: Double,
        floor: Double,
        increment: Double
    ) -> [WarmupSet] {
        var result: [WarmupSet] = []
        var last = floor
        for step in scheme {
            let weight = round(working * step.fraction, to: increment)
            guard weight > last + 0.001, weight < working - 0.001 else { continue }
            result.append(WarmupSet(weightKg: weight, reps: step.reps))
            last = weight
        }
        return result
    }

    static func round(_ value: Double, to increment: Double) -> Double {
        guard increment > 0 else { return value }
        return (value / increment).rounded() * increment
    }
}
