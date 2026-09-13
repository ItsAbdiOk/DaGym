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
    /// One session's worth of stimulus on a muscle, scored against the lifter's own reference.
    public struct SessionStimulus: Sendable {
        /// When the session's last set on this muscle was performed.
        public var date: Date
        /// `Σ effort × share` over the session's sets, before any normalisation.
        public var raw: Double
        /// The reference (in primary-set-equivalents) this session was scored against.
        public var reference: Double
        /// `raw × recoveryFatigueScale / reference` — what `fatigue` decays from.
        public var normalised: Double
    }

    /// `fatigue_m(now) = Σ normalised_session × e^(−Δt/τ_m)` over every session that touched
    /// `m`. Each session is scored against a *causal*, downward-only reference: it starts at
    /// `TrainingConstants.recoveryFatigueScale` and after each session moves toward that
    /// session's raw size (EWMA, `recoveryReferenceSmoothing`) only when that is lower — so a
    /// lifter whose sessions are habitually small feels a normal session as a normal session,
    /// a first-ever big one as a shock, and deleting a workout can never *raise* fatigue.
    /// Events dated after `now` are ignored rather than contributing negative decay.
    public static func fatigue(events: [StimulusEvent], now: Date) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        let byMuscle = Dictionary(grouping: events.filter { $0.date <= now }, by: \.muscle)
        for (muscle, muscleEvents) in byMuscle {
            let tau = muscle.recoveryTimeConstantHours
            var reference = TrainingConstants.recoveryFatigueScale
            var total = 0.0
            for session in sessions(muscleEvents) {
                let raw = session.reduce(0.0) { $0 + $1.effort * $1.share }
                let factor = TrainingConstants.recoveryFatigueScale / reference
                for event in session {
                    let deltaHours = now.timeIntervalSince(event.date) / 3600
                    total += event.effort * event.share * factor * exp(-deltaHours / tau)
                }
                reference = nextReference(after: raw, current: reference)
            }
            result[muscle] = total
        }
        return result
    }

    /// The per-session breakdown behind `fatigue`, oldest session first, for tests and any
    /// "why is this muscle spent" detail. Events after `now` are ignored.
    public static func sessionStimuli(events: [StimulusEvent], now: Date) -> [Muscle: [SessionStimulus]] {
        var result: [Muscle: [SessionStimulus]] = [:]
        let byMuscle = Dictionary(grouping: events.filter { $0.date <= now }, by: \.muscle)
        for (muscle, muscleEvents) in byMuscle {
            var reference = TrainingConstants.recoveryFatigueScale
            var stimuli: [SessionStimulus] = []
            for session in sessions(muscleEvents) {
                let raw = session.reduce(0.0) { $0 + $1.effort * $1.share }
                let date = session.map(\.date).max() ?? now
                stimuli.append(SessionStimulus(
                    date: date, raw: raw, reference: reference,
                    normalised: raw * TrainingConstants.recoveryFatigueScale / reference
                ))
                reference = nextReference(after: raw, current: reference)
            }
            result[muscle] = stimuli
        }
        return result
    }

    /// Strength retention per muscle, 1.0 (fully retained) down to `retentionFloor`: full for
    /// `retentionFullDays` after the last counting set, then halving every
    /// `retentionHalfLifeDays`. Every muscle appears; one never trained sits at the floor.
    public static func retention(lastTrained: [Muscle: Date], now: Date) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for muscle in Muscle.allCases {
            guard let last = lastTrained[muscle] else {
                result[muscle] = TrainingConstants.retentionFloor
                continue
            }
            let days = max(0, now.timeIntervalSince(last) / 86_400)
            let idle = days - TrainingConstants.retentionFullDays
            guard idle > 0 else {
                result[muscle] = 1
                continue
            }
            let decayed = pow(0.5, idle / TrainingConstants.retentionHalfLifeDays)
            result[muscle] = max(TrainingConstants.retentionFloor, decayed)
        }
        return result
    }

    /// `retention(lastTrained:now:)` over the last event (with a non-zero share) per muscle.
    public static func retention(events: [StimulusEvent], now: Date) -> [Muscle: Double] {
        var lastTrained: [Muscle: Date] = [:]
        for event in events where event.share > 0 && event.date <= now {
            if let existing = lastTrained[event.muscle], existing >= event.date { continue }
            lastTrained[event.muscle] = event.date
        }
        return retention(lastTrained: lastTrained, now: now)
    }

    /// Muscles not fully retained (`retention < 1`), least retained first; ties in body order
    /// (`Muscle.allCases`). The graded "detraining" list behind the Balance section.
    public static func detrainedMuscles(
        retention: [Muscle: Double]
    ) -> [(muscle: Muscle, retention: Double)] {
        let bodyOrder = Dictionary(uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) })
        return Muscle.allCases
            .compactMap { muscle -> (muscle: Muscle, retention: Double)? in
                guard let value = retention[muscle], value < 1 else { return nil }
                return (muscle: muscle, retention: value)
            }
            .sorted { lhs, rhs in
                lhs.retention == rhs.retention
                    ? bodyOrder[lhs.muscle, default: 0] < bodyOrder[rhs.muscle, default: 0]
                    : lhs.retention < rhs.retention
            }
    }

    /// Splits one muscle's events into sessions: sorted by date, a new session starts whenever
    /// the gap from the previous event exceeds `recoverySessionGapHours`.
    private static func sessions(_ events: [StimulusEvent]) -> [[StimulusEvent]] {
        let sorted = events.sorted { $0.date < $1.date }
        var sessions: [[StimulusEvent]] = []
        var current: [StimulusEvent] = []
        let gap = TrainingConstants.recoverySessionGapHours * 3600
        for event in sorted {
            if let last = current.last, event.date.timeIntervalSince(last.date) > gap {
                sessions.append(current)
                current = []
            }
            current.append(event)
        }
        if !current.isEmpty { sessions.append(current) }
        return sessions
    }

    /// Downward-only EWMA step: the reference never rises above where it already is, and a
    /// session with no real stimulus (warm-ups only) leaves it alone.
    private static func nextReference(after raw: Double, current: Double) -> Double {
        guard raw > 0 else { return current }
        let alpha = TrainingConstants.recoveryReferenceSmoothing
        return min(current, alpha * raw + (1 - alpha) * current)
    }

    /// Saturating 0…1 "how recovered is it" score, 1 = fully fresh (no fatigue), approaching 0
    /// as fatigue grows without bound: `1 / (1 + fatigue / k)` with
    /// `k = TrainingConstants.recoveryFatigueScale`. Raw fatigue is an (effort-weighted) set
    /// count, so it has to be normalised before saturating — without `k` a single hard set
    /// read 50 % spent and a 10-set chest day stayed "spent" for four days. With k = 6 one hard
    /// session's worth of primary sets reads 50 % and clears the headline threshold in ~72 h.
    public static func recoveredScore(fatigue: Double) -> Double {
        1 / (1 + max(0, fatigue) / TrainingConstants.recoveryFatigueScale)
    }

    /// The raw-fatigue value at which `map` reads `spent` — the threshold to hand to
    /// `recoveredBy(fatigue:tau:threshold:)` for a "spent" score such as
    /// `TrainingConstants.recoveryHeadlineThreshold`.
    public static func fatigueThreshold(spent: Double) -> Double {
        guard spent > 0, spent < 1 else { return spent <= 0 ? 0 : .infinity }
        return TrainingConstants.recoveryFatigueScale * spent / (1 - spent)
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
