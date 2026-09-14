import Foundation

/// One set's contribution to a muscle's fatigue: how much (`share`), how hard (`effort`) and
/// when. Warm-ups contribute nothing — callers simply don't emit an event for them (or, same
/// thing, emit one with `share == 0`).
public struct StimulusEvent: Sendable {
    /// The muscle this stimulus lands on.
    public var muscle: Muscle
    /// 1.0 for a primary mover, `Recovery.secondaryShare` for a secondary one.
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

/// How one logged set becomes a `StimulusEvent`: how much of a set it counts as, and how hard
/// it was. The single place those two conventions are decided, so every caller agrees.
///
/// Two judgement calls are settled here:
///
/// 1. **A drop or rest-pause chunk is not a whole extra set.** It is a continuation of the set
///    before it at a lower load or after a few seconds' rest, so it counts as
///    `recoveryContinuationSetWeight` (½) of one. Counting each drop in full made a
///    triple-drop read as three primary sets — half a "hard session" from one exercise entry.
///    Stats elsewhere (`SetKind.countsTowardStats`) still count it as a logged set; this weight
///    is only about stimulus.
/// 2. **`.failure` and `.amrap` with no rating are maximal.** The kind already says the set was
///    taken to failure, so it gets the RIR-0 effort of 1.0 rather than the 0.75 used for a set
///    nobody rated — matching `PerformedSet.isHard`, which counts those kinds as hard without
///    a rating. Everything else unrated stays at `recoveryUnratedEffort`.
public enum StimulusAttribution {
    /// How much of a set this kind counts as: 0 for a warm-up, ½ for a drop/rest-pause
    /// continuation, 1 for a real working set.
    public static func setWeight(kind: SetKind) -> Double {
        switch kind {
        case .warmup: 0
        case .drop, .restPause: TrainingConstants.recoveryContinuationSetWeight
        case .working, .amrap, .failure: 1
        }
    }

    /// `setWeight` scaled by the mover's role: a secondary mover takes `Recovery.secondaryShare`
    /// of what a primary one does — the same weight the volume charts use, not a second opinion.
    public static func share(kind: SetKind, isPrimary: Bool) -> Double {
        setWeight(kind: kind) * (isPrimary ? 1 : Recovery.secondaryShare)
    }

    /// Effort factor: RIR 0 → 1.0, RIR ≥ 4 → 0.5, linear in between; unrated `.failure`/`.amrap`
    /// → 1.0 (the kind is the rating); anything else unrated → `recoveryUnratedEffort`.
    public static func effort(kind: SetKind, rpe: Double?) -> Double {
        guard let rpe else {
            return kind == .failure || kind == .amrap ? 1.0 : TrainingConstants.recoveryUnratedEffort
        }
        let rir = Effort(rpe: rpe).rir
        guard rir > 0 else { return 1.0 }
        guard rir < 4 else { return 0.5 }
        return 1.0 - Double(rir) * 0.125
    }
}

/// Muscle-fatigue math (§7 of the plan): exponential decay per muscle, mapped to the body map's
/// recovery display and to plain-language copy.
public enum Recovery {
    /// What a secondary mover contributes relative to a primary one, for callers building
    /// `StimulusEvent`s. Aliases `SessionStats.secondaryMuscleShare` so fatigue, the body map
    /// and the volume charts cannot drift apart again.
    public static let secondaryShare = SessionStats.secondaryMuscleShare

    /// One session's worth of stimulus on a muscle: what it was worth when it was logged, and
    /// what is left of it now.
    public struct SessionStimulus: Sendable {
        /// When the session's last set on this muscle was performed.
        public var date: Date
        /// `Σ effort × share` over the session's sets, in primary-set-equivalents.
        public var raw: Double
        /// What this session still contributes to `fatigue` at `now`, i.e. `raw` after decay.
        public var remaining: Double
    }

    /// `fatigue_m(now) = Σ_sets effort × share × e^(−Δt/τ_m)` over every set that touched `m`.
    ///
    /// The unit is the **primary-set-equivalent**: one set of a primary mover taken to failure,
    /// logged this instant, is 1.0. A secondary mover is half a set (`share`), an easy set is
    /// half a hard one (`effort`), and everything decays with the muscle's own time constant.
    /// The scale is absolute — `TrainingConstants.recoveryFatigueScale` (6) of them undecayed
    /// reads 50 % on the map — so the number carries volume information: twice the work reads
    /// higher, always, for every lifter.
    ///
    /// Deliberately **not** normalised against the lifter's own habits. An earlier version
    /// divided every session by a downward-only running average of session size, which made a
    /// later session read as much as 2× more fatiguing because a *lighter* one preceded it, and
    /// converged so that any habitually small stimulus (a single calf set, any secondary-only
    /// muscle) read the same ~50 % as a full primary day — the map stopped carrying volume and
    /// only showed "bigger than usual". Each set now contributes exactly what it is worth,
    /// independent of every other set, which also means nothing steps when an old workout
    /// leaves the caller's window: a session only ever loses influence by decaying.
    ///
    /// Events dated after `now` are ignored rather than contributing negative decay.
    public static func fatigue(events: [StimulusEvent], now: Date) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        let byMuscle = Dictionary(grouping: events.filter { $0.date <= now }, by: \.muscle)
        for (muscle, muscleEvents) in byMuscle {
            result[muscle] = muscleEvents.reduce(0.0) { total, event in
                total + remaining(of: event, at: now, tau: muscle.recoveryTimeConstantHours)
            }
        }
        return result
    }

    /// The per-session breakdown behind `fatigue`, oldest session first, for tests and any
    /// "why is this muscle spent" detail. Events after `now` are ignored.
    public static func sessionStimuli(events: [StimulusEvent], now: Date) -> [Muscle: [SessionStimulus]] {
        var result: [Muscle: [SessionStimulus]] = [:]
        let byMuscle = Dictionary(grouping: events.filter { $0.date <= now }, by: \.muscle)
        for (muscle, muscleEvents) in byMuscle {
            let tau = muscle.recoveryTimeConstantHours
            result[muscle] = sessions(muscleEvents).map { session in
                SessionStimulus(
                    date: session.map(\.date).max() ?? now,
                    raw: session.reduce(0.0) { $0 + $1.effort * $1.share },
                    remaining: session.reduce(0.0) { $0 + remaining(of: $1, at: now, tau: tau) }
                )
            }
        }
        return result
    }

    private static func remaining(of event: StimulusEvent, at now: Date, tau: Double) -> Double {
        let deltaHours = now.timeIntervalSince(event.date) / 3600
        return event.effort * event.share * exp(-deltaHours / tau)
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
            // Descriptive, like the rest of the recovery copy: what was logged, not what it did
            // to the lifter.
            return ("Everything's fresh", "No muscle group has taken much work recently.")
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
