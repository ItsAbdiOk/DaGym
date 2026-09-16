import Foundation

/// Where the latest bodyweight stands against the lifter's goal, for Home's bodyweight tile
/// (OpenGym parity 50). Pure: the tile passes in the two readings it already has.
public enum BodyweightGoal {
    /// Which way the recent change (the 30-day delta) is moving relative to the goal.
    public enum Trend: Equatable, Sendable {
        /// Closer to the goal than 30 days ago.
        case toward
        /// Further from it.
        case away
        /// No comparison reading, no meaningful change, or already at the goal.
        case flat
    }

    public struct Status: Equatable, Sendable {
        /// kg between the latest reading and the goal, never negative.
        public var remainingKg: Double
        /// The remaining distance rounds to zero in the lifter's unit — "80.1 kg" against an
        /// 80 kg goal is at goal, not "0.1 to go".
        public var isReached: Bool
        public var trend: Trend

        public init(remainingKg: Double, isReached: Bool, trend: Trend) {
            self.remainingKg = remainingKg
            self.isReached = isReached
            self.trend = trend
        }
    }

    /// Below this the 30-day change is noise, same threshold the tile's delta line uses.
    public static let flatThresholdKg = 0.1

    /// - Parameters:
    ///   - currentKg: the latest reading.
    ///   - goalKg: the goal.
    ///   - deltaKg: `currentKg` minus the reading 30 days ago; nil without one.
    ///   - unit: decides when the remaining distance has rounded away to nothing.
    public static func status(
        currentKg: Double, goalKg: Double, deltaKg: Double?, unit: WeightUnit
    ) -> Status {
        let signedRemaining = goalKg - currentKg
        let step = unit.displayStep
        let displayRemaining = (unit.display(kg: abs(signedRemaining)) / step).rounded() * step
        let isReached = displayRemaining < step / 2
        guard !isReached, let deltaKg, abs(deltaKg) >= flatThresholdKg else {
            return Status(remainingKg: abs(signedRemaining), isReached: isReached, trend: .flat)
        }
        // Moving the way the goal lies: a gain goal wants a positive delta, a loss goal a negative one.
        let toward = (signedRemaining > 0) == (deltaKg > 0)
        return Status(remainingKg: abs(signedRemaining), isReached: false, trend: toward ? .toward : .away)
    }
}
