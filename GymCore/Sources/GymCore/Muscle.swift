import Foundation

/// The 14 named body-map regions. Drives the "muscles hit" thumbnail, the
/// live workout map and the recovery heatmap.
public enum Muscle: String, CaseIterable, Codable, Sendable, Identifiable {
    case traps, delts, chest, abs, obliques, biceps, forearms, quads, calves
    case lats, triceps, lowerBack, glutes, hams

    public var id: String { rawValue }

    public var isFront: Bool {
        switch self {
        case .traps, .delts, .chest, .abs, .obliques, .biceps, .forearms, .quads, .calves: true
        case .lats, .triceps, .lowerBack, .glutes, .hams: false
        }
    }

    public var displayName: String {
        switch self {
        case .traps: "Traps"
        case .delts: "Delts"
        case .chest: "Chest"
        case .abs: "Abs"
        case .obliques: "Obliques"
        case .biceps: "Biceps"
        case .forearms: "Forearms"
        case .quads: "Quads"
        case .calves: "Calves"
        case .lats: "Lats"
        case .triceps: "Triceps"
        case .lowerBack: "Lower back"
        case .glutes: "Glutes"
        case .hams: "Hamstrings"
        }
    }

    /// Recovery time constant in hours (§7 of the plan).
    public var recoveryTimeConstantHours: Double {
        switch self {
        case .biceps, .triceps, .forearms, .calves, .abs, .obliques: 24
        case .chest, .lats, .traps, .delts: 36
        case .quads, .hams, .glutes, .lowerBack: 48
        }
    }
}
