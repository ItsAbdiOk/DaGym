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
}
