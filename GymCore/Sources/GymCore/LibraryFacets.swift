import Foundation

/// Which library filter chips would still find something. Given the rows every *other* filter
/// already lets through (search text, favourites, custom, the equipment profile), one pass
/// answers both chip rows at once: a muscle chip stays live if a row matching the selected
/// equipment works that muscle; an equipment chip stays live if a row working the selected
/// muscle uses it. The per-muscle counts also drive the "by muscle" body map.
public enum LibraryFacets {
    /// The parts of one library row the facets read.
    public struct Entry: Sendable {
        public var primary: [Muscle]
        public var secondary: [Muscle]
        public var equipment: String

        public init(primary: [Muscle], secondary: [Muscle], equipment: String) {
            self.primary = primary
            self.secondary = secondary
            self.equipment = equipment
        }
    }

    public struct Remaining: Equatable, Sendable {
        /// Rows per muscle under the selected equipment (and `includeSecondary`); a muscle with
        /// no row is absent, so `muscles` reads as "chips worth tapping".
        public var muscleCounts: [Muscle: Int]
        /// Rows per equipment raw value under the selected muscle.
        public var equipmentCounts: [String: Int]

        public init(muscleCounts: [Muscle: Int] = [:], equipmentCounts: [String: Int] = [:]) {
            self.muscleCounts = muscleCounts
            self.equipmentCounts = equipmentCounts
        }

        public var muscles: Set<Muscle> { Set(muscleCounts.keys) }
        public var equipment: Set<String> { Set(equipmentCounts.keys) }
    }

    /// One O(n) pass over `entries`. `includeSecondary` mirrors the list's own muscle match:
    /// on, a row counts for every muscle it works; off, only for its primary movers.
    public static func remaining(
        _ entries: some Sequence<Entry>, selectedMuscle: Muscle?, selectedEquipment: String?,
        includeSecondary: Bool = true
    ) -> Remaining {
        var muscleCounts: [Muscle: Int] = [:]
        var equipmentCounts: [String: Int] = [:]
        for entry in entries {
            let muscles = includeSecondary ? entry.primary + entry.secondary : entry.primary
            if selectedEquipment == nil || entry.equipment == selectedEquipment {
                // A muscle listed as both primary and secondary is one row, not two.
                for muscle in Set(muscles) { muscleCounts[muscle, default: 0] += 1 }
            }
            if selectedMuscle.map(muscles.contains) ?? true {
                equipmentCounts[entry.equipment, default: 0] += 1
            }
        }
        return Remaining(muscleCounts: muscleCounts, equipmentCounts: equipmentCounts)
    }

    /// Body-map tints for "explore by muscle": the best-stocked muscle reads 1.0 and every
    /// muscle with at least one row stays on the lit side of the map's lowest step
    /// (`minimumLit`), so a group with a handful of exercises is visibly tappable rather than
    /// inert. Muscles with no row are left out — the map draws them inert and takes no tap.
    public static func mapIntensity(counts: [Muscle: Int]) -> [Muscle: Double] {
        guard let top = counts.values.max(), top > 0 else { return [:] }
        return counts.filter { $0.value > 0 }.mapValues {
            $0 == top ? 1 : minimumLit + (1 - minimumLit) * Double($0) / Double(top)
        }
    }

    /// Just over one third: `BodyMapView`'s hit mode rounds `value × 3`, so anything ≥ ⅙ lands
    /// on the first coral step, and this keeps a one-exercise muscle clearly off inert.
    static let minimumLit = 0.34
}
