import Foundation

/// The 5/3/1-style 4-week wave used by `.percentOfTrainingMax` (plan.md §7):
/// week → an ordered list of (percent of training max, reps, is the set AMRAP).
public struct WaveScheme: Codable, Hashable, Sendable {
    public struct WeekSet: Codable, Hashable, Sendable {
        public var percent: Double
        public var reps: Int
        public var isAMRAP: Bool

        public init(percent: Double, reps: Int, isAMRAP: Bool) {
            self.percent = percent
            self.reps = reps
            self.isAMRAP = isAMRAP
        }
    }

    /// Week number (1...4) to that week's prescribed sets, in order.
    public var weeks: [Int: [WeekSet]]

    public init(weeks: [Int: [WeekSet]]) {
        self.weeks = weeks
    }

    /// The default wave from `TrainingConstants.waveScheme`.
    public static let classic = WaveScheme(
        weeks: TrainingConstants.waveScheme.mapValues { week in
            week.map { WeekSet(percent: $0.percent, reps: $0.reps, isAMRAP: $0.isAMRAP) }
        }
    )
}

/// How the next session's numbers are computed for one routine exercise
/// (plan.md §6.5, §7). Overridable per exercise.
public enum ProgressionRule: Codable, Hashable, Sendable {
    /// Add a fixed weight when every working set hits its target.
    case linear(incrementKg: Double)
    /// Climb reps within [low, high]; at `high`, add weight and reset to `low`.
    case doubleProgression(low: Int, high: Int, incrementKg: Double)
    /// Straight sets plus a final AMRAP set that drives the next increment.
    case linearAMRAP(incrementKg: Double)
    /// Load derived each session from the last set's implied e1RM at a target RPE.
    case rpeBased(targetRPE: Double)
    /// Percent of a rolling training max, following a multi-week wave.
    case percentOfTrainingMax(scheme: WaveScheme)
    /// Bodyweight movement: reps up to a ceiling, then sets, then a harder variation.
    case bodyweight(repCeiling: Int, maxSets: Int)
    /// Assisted movement: assistance steps down as reps are hit.
    case assisted(stepKg: Double)
    /// Timed hold: seconds step up as the hold is hit.
    case timed(stepSeconds: Int)

    public var displayName: String {
        switch self {
        case .linear: "Linear"
        case .doubleProgression: "Double progression"
        case .linearAMRAP: "Linear + AMRAP"
        case .rpeBased: "RPE-based"
        case .percentOfTrainingMax: "Percentage / training max"
        case .bodyweight: "Bodyweight"
        case .assisted: "Assisted"
        case .timed: "Timed"
        }
    }

    /// One sentence for the routine-builder card.
    public var explanation: String {
        switch self {
        case .linear(let incrementKg):
            return "Adds \(WeightFormat.kg(incrementKg)) kg once every working set hits its target."
        case .doubleProgression(let low, let high, let incrementKg):
            return "Climbs reps from \(low) to \(high), then adds \(WeightFormat.kg(incrementKg)) kg " +
                "and drops back to \(low) reps."
        case .linearAMRAP(let incrementKg):
            return "Adds \(WeightFormat.kg(incrementKg)) kg (double if the last set crushes its target reps)."
        case .rpeBased(let targetRPE):
            return "Recalculates load each session to hit your target reps at RPE \(rpeText(targetRPE))."
        case .percentOfTrainingMax:
            return "Programs a 4-week wave off your training max, bumping it each cycle " +
                "(capped by your AMRAP sets)."
        case .bodyweight(let repCeiling, let maxSets):
            return "Adds reps up to \(repCeiling), then a set (up to \(maxSets)), then suggests going harder."
        case .assisted(let stepKg):
            return "Removes \(WeightFormat.kg(stepKg)) kg of assistance once every rep is hit."
        case .timed(let stepSeconds):
            return "Adds \(stepSeconds) s to the hold once every set hits its target."
        }
    }

    private func rpeText(_ rpe: Double) -> String {
        rpe == rpe.rounded() ? String(Int(rpe)) : String(rpe)
    }
}
