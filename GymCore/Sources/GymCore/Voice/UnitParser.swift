import Foundation

/// Resolves a bare or unit-tagged number into canonical kg or seconds,
/// and understands "N plates" / "a plate and a half" phrasing.
public enum UnitParser {
    /// Converts a spoken weight number to canonical kg. `unit == nil` means the
    /// number carried no explicit unit word, so the user's preference applies.
    public static func weightKg(number: Double, unit: UnitKind?, context: ParseContext) -> Double {
        switch unit {
        case .kg: return number
        case .lb: return WeightUnit.lb.toKg(number)
        case .plates: return platesToKg(perSide: number, context: context)
        case .seconds, .minutes, .km, .miles, .none: return context.unit.toKg(number)
        }
    }

    /// Converts a spoken distance number to canonical metres; nil for a non-distance unit.
    public static func distanceMeters(number: Double, unit: UnitKind?) -> Double? {
        switch unit {
        case .km: return DistanceUnit.km.toMeters(number)
        case .miles: return DistanceUnit.mi.toMeters(number)
        case .kg, .lb, .plates, .seconds, .minutes, .none: return nil
        }
    }

    /// Converts a spoken duration number to seconds.
    public static func durationSeconds(number: Double, unit: UnitKind?) -> Int {
        unit == .minutes ? Int((number * 60).rounded()) : Int(number.rounded())
    }

    /// Bar weight plus `perSide` plates (each side), using the gym's plate
    /// vocabulary: 20 kg / 45 lb plates, "a quarter" = 5 kg (25 lb) per owner's answer.
    public static func platesToKg(perSide: Double, context: ParseContext) -> Double {
        let bar = context.bar ?? .olympic
        return bar.weightKg + 2 * plateSideWeightKg(count: perSide, unit: context.unit)
    }

    private static func plateSideWeightKg(count: Double, unit: WeightUnit) -> Double {
        let whole = count.rounded(.down)
        let fraction = count - whole
        let base = unit == .kg ? 20.0 : WeightUnit.lb.toKg(45)
        let quarter = unit == .kg ? 5.0 : WeightUnit.lb.toKg(25)
        var fractionWeight = 0.0
        if abs(fraction - 0.5) < 0.01 {
            fractionWeight = base / 2
        } else if abs(fraction - 0.25) < 0.01 {
            fractionWeight = quarter
        } else if abs(fraction - 0.75) < 0.01 {
            fractionWeight = quarter + base / 2
        }
        return whole * base + fractionWeight
    }

    /// Matches "[<number>|a] plate(s) [and a half|and a quarter]" starting at `index`.
    /// Returns the per-side plate count and words consumed.
    public static func platePhrase(_ words: [String], at index: Int) -> (perSide: Double, consumed: Int)? {
        var idx = index
        var count = 1.0
        if let (value, used) = NumberWords.parse(words, at: idx) {
            count = value
            idx += used
        } else if words[idx] == "a" || words[idx] == "an" {
            idx += 1
        } else {
            return nil
        }
        guard idx < words.count, words[idx] == "plate" || words[idx] == "plates" else { return nil }
        idx += 1
        if idx + 2 < words.count, words[idx] == "and",
           words[idx + 1] == "a" || words[idx + 1] == "an" {
            if words[idx + 2] == "half" {
                count += 0.5; idx += 3
            } else if words[idx + 2] == "quarter" {
                count += 0.25; idx += 3
            }
        }
        return (count, idx - index)
    }
}
