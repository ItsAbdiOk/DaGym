import Foundation

/// The unit a user sees weights in. Storage is always kg (see plan.md §3);
/// this type is the single place conversions and unit-aware formatting happen.
public enum WeightUnit: String, CaseIterable, Codable, Sendable {
    case kg
    case lb

    /// kg per lb, matching the conversion used throughout this type.
    private static let kgPerLb = 1 / 2.20462

    public var symbol: String {
        switch self {
        case .kg: return "kg"
        case .lb: return "lb"
        }
    }

    /// How finely a displayed value is rounded: quarter-kg, or half-pound.
    public var displayStep: Double {
        switch self {
        case .kg: return 0.25
        case .lb: return 0.5
        }
    }

    /// Converts a canonical kg value to this unit, unrounded.
    public func display(kg: Double) -> Double {
        switch self {
        case .kg: return kg
        case .lb: return kg * 2.20462
        }
    }

    /// Converts a value already expressed in this unit back to kg.
    public func toKg(_ value: Double) -> Double {
        switch self {
        case .kg: return value
        case .lb: return value * Self.kgPerLb
        }
    }

    /// Formats a canonical kg value in this unit, rounded to `displayStep`,
    /// dropping a trailing ".0" (e.g. "82.5", "180").
    public func format(kg: Double, decimals: Int = 1) -> String {
        let step = displayStep
        let raw = display(kg: kg)
        let rounded = (raw / step).rounded() * step
        if abs(rounded - rounded.rounded()) < 0.001 {
            return String(Int(rounded.rounded()))
        }
        // A value on the half-unit grid (82.5, 220.5) prints cleanly at `decimals`. One that
        // isn't — kg's own quarter-step (61.25) — isn't exactly representable in binary
        // floating point, so `decimals == 1` truncates it to "61.2"; two decimals round it right.
        let onHalfGrid = abs((rounded / 0.5).rounded() * 0.5 - rounded) < 0.001
        let effectiveDecimals = onHalfGrid ? decimals : max(decimals, 2)
        return String(format: "%.\(effectiveDecimals)f", rounded)
    }

    /// The bar/dumbbell increment a set is usually adjusted by in this unit,
    /// expressed in kg: 2.5 kg, or 5 lb.
    public var defaultIncrementKg: Double {
        switch self {
        case .kg: return 2.5
        case .lb: return toKg(5)
        }
    }

    /// The bar this unit's lifters expect by default: a 20 kg Olympic bar,
    /// or a 45 lb bar (~20.41 kg).
    public var defaultBar: Bar {
        switch self {
        case .kg: return .olympic
        case .lb: return Bar(name: "Olympic", weightKg: toKg(45))
        }
    }

    /// A typical plate inventory for lifters in this unit: the standard kg
    /// set, or the standard 45/35/25/10/5/2.5 lb set converted to kg.
    public static func plateStock(for unit: WeightUnit) -> [PlateStock] {
        switch unit {
        case .kg:
            return PlateStock.standardKg
        case .lb:
            let poundsAndCounts: [(Double, Int)] = [
                (45, 4), (35, 4), (25, 2), (10, 4), (5, 4), (2.5, 4)
            ]
            return poundsAndCounts.map { pounds, count in
                PlateStock(weightKg: unit.toKg(pounds), count: count)
            }
        }
    }
}
