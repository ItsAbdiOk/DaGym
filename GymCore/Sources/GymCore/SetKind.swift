import Foundation

/// Kind of a logged or planned set. Warm-ups never count toward 1RM,
/// progression, PRs or fatigue.
public enum SetKind: String, CaseIterable, Codable, Sendable {
    case warmup, working, amrap, drop, failure, restPause

    /// The one- or two-character badge shown in the set row.
    public var badge: String {
        switch self {
        case .warmup: "W"
        case .working: ""
        case .amrap: "A+"
        case .drop: "D"
        case .failure: "F"
        case .restPause: "R"
        }
    }

    public var displayName: String {
        switch self {
        case .warmup: "Warm-up"
        case .working: "Working"
        case .amrap: "AMRAP"
        case .drop: "Drop set"
        case .failure: "To failure"
        case .restPause: "Rest-pause"
        }
    }

    public var countsTowardStats: Bool { self != .warmup }

    /// Whether the progression engine may judge this set against a planned set.
    ///
    /// Only a straight working set and an AMRAP are *the* work the plan asked for. A drop set,
    /// a set taken to failure and a rest-pause continuation are all extra work bolted onto a
    /// set that already happened — they carry a lower load or a broken rest, and the plan has
    /// no slot for them. Judging them by position paired the plan's set 2 with a 64 kg drop
    /// after a 80 kg set 1 and read the session as a miss; two of those and the engine deloaded
    /// a lift that was progressing.
    ///
    /// Distinct from `countsTowardStats`, which is about volume, PRs and the set counts the UI
    /// shows — a drop set is real work and counts there.
    public var countsTowardProgression: Bool {
        switch self {
        case .working, .amrap: true
        case .warmup, .drop, .failure, .restPause: false
        }
    }
}
