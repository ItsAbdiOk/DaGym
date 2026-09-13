import Foundation

/// One set's contribution to a muscle's fatigue: how much (`share`), how hard (`effort`) and
/// when. Warm-ups contribute nothing — callers simply don't emit an event for them (or, same
/// thing, emit one with `share == 0`).
public struct StimulusEvent: Sendable {
    /// The muscle this stimulus lands on.
    public var muscle: Muscle
    /// 1.0 for a primary mover, 0.5 for a secondary one.
    public var share: Double
    /// Effort factor: RIR 0 → 1.0, RIR ≥ 4 → 0.5, unknown effort → 0.75.
    public var effort: Double
    /// When the set was performed.
    public var date: Date

    public init(muscle: Muscle, share: Double, effort: Double, date: Date) {
        self.muscle = muscle
        self.share = share
        self.effort = effort
        self.date = date
    }
}

/// Muscle-fatigue math (§7 of the plan): exponential decay per muscle, mapped to the body map's
/// recovery display and to plain-language copy.
public enum Recovery {
    /// `fatigue_m(now) = Σ effort × share × e^(−Δt/τ_m)` over every event that touched `m`.
    /// Events dated after `now` are ignored rather than contributing negative decay.
    public static func fatigue(events: [StimulusEvent], now: Date) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for event in events {
            let deltaHours = now.timeIntervalSince(event.date) / 3600
            guard deltaHours >= 0 else { continue }
            let tau = event.muscle.recoveryTimeConstantHours
            let decay = exp(-deltaHours / tau)
            result[event.muscle, default: 0] += event.effort * event.share * decay
        }
        return result
    }

    /// Saturating 0…1 "how recovered is it" score, 1 = fully fresh (no fatigue), approaching 0
    /// as fatigue grows without bound. Uses `1 / (1 + fatigue)` rather than `e^(−fatigue)`
    /// because it decays slower for small fatigue values — a single easy set shouldn't read as
    /// "still 90%+ fresh only because of exponential steepness" — while both curves agree at the
    /// endpoints (fatigue 0 → score 1, fatigue → ∞ → score 0).
    public static func recoveredScore(fatigue: Double) -> Double {
        1 / (1 + max(0, fatigue))
    }

    /// The body map's recovery mode wants 0 (fresh) … 1 (spent) — the inverse of
    /// `recoveredScore`. Only muscles with at least one event appear.
    public static func map(events: [StimulusEvent], now: Date) -> [Muscle: Double] {
        fatigue(events: events, now: now).mapValues { 1 - recoveredScore(fatigue: $0) }
    }

    /// Solves `fatigue × e^(−t/τ) < threshold` for `t`: the time until this muscle's fatigue
    /// decays below `threshold`. Zero when it's already there (or `threshold` is non-positive).
    public static func recoveredBy(fatigue: Double, tau: Double, threshold: Double) -> TimeInterval {
        guard threshold > 0, fatigue > threshold else { return 0 }
        let hours = tau * log(fatigue / threshold)
        return max(0, hours * 3600)
    }

    /// Plain-language recovery headline for the Home/Progress screens.
    public static func headline(map: [Muscle: Double]) -> (title: String, body: String) {
        guard !map.isEmpty else {
            return ("Nothing logged yet", "Log a workout to start tracking recovery.")
        }
        let sorted = map.sorted { $0.value > $1.value }
        let threshold = TrainingConstants.recoveryHeadlineThreshold
        guard let mostSpent = sorted.first, mostSpent.value > threshold else {
            return ("Everything's fresh", "No muscle group is carrying meaningful fatigue right now.")
        }
        let title = "\(mostSpent.key.displayName) still spent"
        let freshNames = sorted.filter { $0.value <= threshold }.map(\.key.displayName)
        return (title, freshBody(freshNames))
    }

    private static func freshBody(_ freshNames: [String]) -> String {
        guard !freshNames.isEmpty else {
            return "Everything else is still recovering too — an easy day might help."
        }
        let verb = freshNames.count == 1 ? "is" : "are"
        return "\(joinedNames(freshNames)) \(verb) fresh — today's push is fine."
    }

    private static func joinedNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and others"
        }
    }
}
