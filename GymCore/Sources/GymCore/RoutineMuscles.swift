import Foundation

// swiftlint:disable large_tuple
/// Turns a routine's planned exercises into the "muscles hit" body-map
/// intensities, and those intensities into the plain-language "HITS" line
/// shown next to the map (e.g. "Chest, front delts, triceps · light on back").
public enum RoutineMuscles {
    /// Weighted, normalised hit map for a set of planned exercises: primary
    /// muscles count `setCount` sets, secondary muscles count at half
    /// weight, and the result is normalised so the most-worked muscle is
    /// 1.0. An empty exercise list yields an empty map.
    public static func hitMap(
        exercises: [(primary: [Muscle], secondary: [Muscle], setCount: Int)]
    ) -> [Muscle: Double] {
        SessionStats.musclesHit(sets: exercises.map {
            (primary: $0.primary, secondary: $0.secondary, completedCount: $0.setCount)
        })
    }

    /// Coarse region grouping used only for the "light on" clause below —
    /// this is prose, not the body map, so it's deliberately loose.
    private static func region(for muscle: Muscle) -> String {
        switch muscle {
        case .chest: "chest"
        case .delts, .traps: "shoulders"
        case .biceps, .triceps, .forearms: "arms"
        case .abs, .obliques: "core"
        case .lats, .lowerBack: "back"
        case .quads, .hams, .calves, .glutes: "legs"
        }
    }

    /// Builds the "HITS" line from a hit map.
    ///
    /// Wording rule: muscles at or above 0.6 are named individually,
    /// highest first, with only the first capitalised and the rest
    /// lowercase (e.g. "Chest, front delts, triceps"). Muscles between 0.2
    /// and 0.6 are not named individually; instead their regions (see
    /// `region(for:)`) are folded into a trailing "light on <region>"
    /// clause, in descending order of their best muscle's score, deduped.
    /// Muscles below 0.2 are treated as not worked. An empty map, or a map
    /// with nothing at or above 0.2, summarises as "Nothing yet".
    public static func summary(hitMap: [Muscle: Double]) -> String {
        let named = hitMap.filter { $0.value >= 0.6 }.sorted { $0.value > $1.value }
        let light = hitMap.filter { $0.value >= 0.2 && $0.value < 0.6 }.sorted { $0.value > $1.value }

        let namedText = named.enumerated()
            .map { index, entry in index == 0 ? entry.key.displayName : entry.key.displayName.lowercased() }
            .joined(separator: ", ")

        var regions: [String] = []
        for entry in light {
            let region = region(for: entry.key)
            if !regions.contains(region) { regions.append(region) }
        }

        if namedText.isEmpty, regions.isEmpty { return "Nothing yet" }
        if regions.isEmpty { return namedText }

        let lightClause = "light on " + regions.joined(separator: " and ")
        guard !namedText.isEmpty else {
            return lightClause.prefix(1).uppercased() + lightClause.dropFirst()
        }
        return "\(namedText) · \(lightClause)"
    }
}
// swiftlint:enable large_tuple
