import Foundation

/// How the active workout lays its exercises out (OpenGym parity 1). `cards` is the full
/// on-deck card with its plate chip, last-3 strip and why-card; `compact` is the same card
/// with only the header and rows; `list` drops the card chrome entirely — one header row per
/// exercise, one dense row per set, every set of every exercise on screen.
///
/// Saved in `Preferences.workoutLayout`; the active screen may override it for one session.
public enum WorkoutLayout: String, CaseIterable, Codable, Sendable, Identifiable {
    case cards
    case list
    case compact

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cards: "Cards"
        case .list: "List"
        case .compact: "Compact"
        }
    }

    /// SF Symbol for the picker rows.
    public var symbolName: String {
        switch self {
        case .cards: "rectangle.stack"
        case .list: "list.bullet"
        case .compact: "rectangle.compress.vertical"
        }
    }

    /// The on-deck card sheds its extras (plate chip, last-3 strip, why-card) in every layout
    /// but `cards`.
    public var showsCardExtras: Bool { self == .cards }

    /// The value a stored raw string resolves to, falling back to the pre-three-way "Compact
    /// layout" toggle so a lifter who had it on keeps it: a missing or unknown raw value with
    /// `legacyCompact` on reads as `.compact`, otherwise `.cards`.
    public init(stored raw: String?, legacyCompact: Bool) {
        if let raw, let layout = WorkoutLayout(rawValue: raw) {
            self = layout
        } else {
            self = legacyCompact ? .compact : .cards
        }
    }
}
