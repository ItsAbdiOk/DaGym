import Foundation

/// One lift's recent trend, as input to deload detection.
public struct LiftSnapshot: Hashable, Sendable {
    public var name: String
    /// Consecutive misses from the lift's `StallState` (linear, linear + AMRAP and double
    /// progression all maintain one).
    public var stalls: Int
    /// e1RM from the last up to 3 sessions, oldest first. Callers must exclude planned
    /// deload sessions (`ExerciseHistoryEntry.wasPlannedDeload`) — a deload week's lower
    /// numbers are not a decline.
    public var e1rmTrend: [Double]
    /// Average RPE at the same load, oldest first, spanning about 2 weeks. Nil when untracked.
    public var rpeAtSameLoadTrend: [Double]?

    public init(name: String, stalls: Int, e1rmTrend: [Double], rpeAtSameLoadTrend: [Double]? = nil) {
        self.name = name
        self.stalls = stalls
        self.e1rmTrend = e1rmTrend
        self.rpeAtSameLoadTrend = rpeAtSameLoadTrend
    }
}

/// A suggested (never forced) deload, with the plain-language evidence.
public struct DeloadSuggestion: Hashable, Sendable {
    public var reason: String

    public init(reason: String) {
        self.reason = reason
    }

    /// Stable across launches (unlike `hashValue`): the app persists the fingerprint the
    /// user dismissed so the same evidence isn't re-suggested every session, while new
    /// evidence still is.
    public var fingerprint: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in reason.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Suggests a deload from stalls, e1RM regression, rising RPE at the same
/// load, or too many hard weeks in a row (plan.md §7).
public enum DeloadDetector {
    /// - Parameters:
    ///   - hardWeeks: consecutive calendar weeks (ending this week) that met the weekly
    ///     workout goal with no planned deload week among them. On its own it only counts
    ///     when some lift is also not moving (a stall, a flat/declining e1RM, or RPE
    ///     creeping up) — a beginner in week 5 of LP who is still adding weight isn't told
    ///     to deload.
    public static func evaluate(lifts: [LiftSnapshot], hardWeeks: Int) -> DeloadSuggestion? {
        var reasons: [String] = []
        reasons.append(contentsOf: stallReasons(lifts))
        reasons.append(contentsOf: trendReasons(lifts))
        if hardWeeks >= TrainingConstants.deloadHardWeeksThreshold,
           !reasons.isEmpty || lifts.contains(where: isNotProgressing) {
            reasons.append("\(hardWeeks) hard weeks in a row without a lighter week")
        }
        guard !reasons.isEmpty else { return nil }
        return DeloadSuggestion(reason: reasons.joined(separator: "; "))
    }

    /// The plan for a suggested deload: a fraction of the normal sets at a fraction of the load.
    public static func deloadPlan(sets: Int, load: Double) -> (sets: Int, loadKg: Double) {
        let newSets = max(1, Int((Double(sets) * TrainingConstants.deloadSetsFraction).rounded()))
        return (sets: newSets, loadKg: load * TrainingConstants.deloadLoadFraction)
    }

    private static func stallReasons(_ lifts: [LiftSnapshot]) -> [String] {
        let stalled = lifts.filter { $0.stalls >= TrainingConstants.deloadStallCount }
        guard stalled.count >= TrainingConstants.deloadMinLiftsStalling else { return [] }
        let names = stalled.map(\.name).joined(separator: ", ")
        let streak = TrainingConstants.deloadStallCount
        return ["\(stalled.count) lifts (\(names)) have stalled \(streak)+ sessions in a row"]
    }

    private static func trendReasons(_ lifts: [LiftSnapshot]) -> [String] {
        var reasons: [String] = []
        for lift in lifts {
            if let decline = e1rmDeclineFraction(lift.e1rmTrend),
               decline > TrainingConstants.deloadE1rmDropFraction {
                let percent = Int((decline * 100).rounded())
                reasons.append("\(lift.name)'s e1RM is down \(percent)% over its last 3 sessions")
            }
            if let rise = rpeRise(lift.rpeAtSameLoadTrend), rise >= TrainingConstants.deloadRpeRiseThreshold {
                reasons.append(
                    "\(lift.name)'s RPE at the same load has risen \(rise) points over the last 2 weeks"
                )
            }
        }
        return reasons
    }

    /// Any sign the lift has stopped moving up: a miss streak, an e1RM trend (of at least
    /// two sessions) that isn't rising, or RPE at the same load creeping up by half a point.
    private static func isNotProgressing(_ lift: LiftSnapshot) -> Bool {
        if lift.stalls >= 1 { return true }
        if lift.e1rmTrend.count >= 2, let first = lift.e1rmTrend.first, let last = lift.e1rmTrend.last,
           last <= first {
            return true
        }
        if let rise = rpeRise(lift.rpeAtSameLoadTrend), rise >= 0.5 { return true }
        return false
    }

    /// Decline of the latest session against the best of the two before it — but only
    /// when the last two points both stepped down, so one off day isn't a "trend".
    private static func e1rmDeclineFraction(_ trend: [Double]) -> Double? {
        guard trend.count >= 3 else { return nil }
        let recent = Array(trend.suffix(3))
        let peak = max(recent[0], recent[1])
        guard peak > 0, recent[2] < recent[1], recent[1] < recent[0] else { return nil }
        return (peak - recent[2]) / peak
    }

    private static func rpeRise(_ trend: [Double]?) -> Double? {
        guard let trend, trend.count >= 2, let first = trend.first, let last = trend.last else { return nil }
        return last - first
    }
}
