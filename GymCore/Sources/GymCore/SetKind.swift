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
}
