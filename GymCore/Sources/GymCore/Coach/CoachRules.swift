import Foundation

/// Namespace for the ten rule implementations. Each rule lives in its own
/// `CoachRules+<Rule>.swift` file and reuses an existing GymCore engine for its actual signal
/// (see each file's header comment) rather than re-deriving one.
enum CoachRules {
    /// A deterministic, calendar-independent key for a date-based fingerprint — stable across
    /// launches, unlike `Date.hashValue` or anything that depends on a `Calendar`.
    static func dateKey(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }

    /// The concrete load a stalled lift should back off to: `deloadLoadFraction` of the stalled
    /// weight, rounded *down* onto that lift's own grid (`LoadGrid`, the same rounding the
    /// progression engine uses) and clamped to a real load strictly below the stalled one.
    ///
    /// Nil when there is no honest number to offer: no grid (bodyweight, assisted, timed work —
    /// "90 % of your bodyweight" is not a prescription), or nothing lighter exists on this
    /// equipment. Callers show a card with no weight rather than an unloadable one.
    static func deloadLoad(for lift: CoachLiftSnapshot, stalledWeightKg: Double) -> Double? {
        guard stalledWeightKg > 0, let grid = lift.loadGrid else { return nil }
        // Wider than the grid's own rounding slack, so "just under" isn't snapped back up —
        // the same epsilon `RuleContext.deloadClamped` uses.
        let epsilon = 0.01
        let candidate = grid.nearestBelow(stalledWeightKg * TrainingConstants.deloadLoadFraction)
        let heaviestBelow = grid.nearestBelow(stalledWeightKg - epsilon)
        let lightest = grid.nearestAbove(0)
        guard heaviestBelow > epsilon, heaviestBelow < stalledWeightKg - epsilon,
              lightest <= heaviestBelow + epsilon else { return nil }
        return min(max(candidate, lightest), heaviestBelow)
    }
}
