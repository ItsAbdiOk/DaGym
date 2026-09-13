import Foundation

/// Effort rating. RPE and RIR are the same scale relabelled: RIR = 10 − RPE.
/// Colour never travels without the plain-language line.
public struct Effort: Hashable, Codable, Sendable {
    public enum Scale: String, Codable, Sendable {
        case rpe, rir
    }

    /// Stored canonically as RPE, 5…10 in half steps allowed.
    public var rpe: Double

    public init(rpe: Double) {
        self.rpe = min(10, max(5, rpe))
    }

    public init(rir: Int) {
        self.init(rpe: Double(10 - rir))
    }

    public var rir: Int { Int((10 - rpe).rounded()) }

    /// Value to show for the user's chosen scale.
    public func displayValue(scale: Scale) -> String {
        switch scale {
        case .rpe:
            if rpe == rpe.rounded() { return String(Int(rpe)) }
            return String(rpe)
        case .rir: return String(rir)
        }
    }

    /// "hard — 2 reps in the tank"
    public var plainLanguage: String {
        switch rpe {
        case ..<6: "Easy — \(rir) left in the tank"
        case ..<7: "Comfortable — \(rir) in the tank"
        case ..<8: "Solid — \(rir) left"
        case ..<9: "Hard — \(rir) reps in the tank"
        case ..<10: "1 rep left"
        default: "Nothing left"
        }
    }

    /// 0 easy … 4 max — index into the effort colour ramp.
    public var level: Int {
        switch rpe {
        case ..<6.5: 0
        case ..<7.5: 1
        case ..<8.5: 2
        case ..<9.5: 3
        default: 4
        }
    }

    /// The pickable steps, RPE 5 → 10.
    public static let steps: [Effort] = stride(from: 5.0, through: 10.0, by: 1.0).map { Effort(rpe: $0) }
}
