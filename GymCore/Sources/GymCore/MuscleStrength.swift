import Foundation

/// The muscle map's Strength mode: per muscle, the lifter's strongest exercises by best
/// estimated 1RM. An exercise files under each of its primary movers (a bench press is a chest
/// lift and a triceps lift); secondary movers don't count — a row's e1RM says nothing about
/// how strong the muscle assisting it is.
public enum MuscleStrength {
    /// One library exercise with a best e1RM on record.
    public struct Lift: Hashable, Sendable {
        public var exerciseID: UUID
        public var name: String
        public var primary: [Muscle]
        public var e1rmKg: Double

        public init(exerciseID: UUID, name: String, primary: [Muscle], e1rmKg: Double) {
            self.exerciseID = exerciseID
            self.name = name
            self.primary = primary
            self.e1rmKg = e1rmKg
        }
    }

    /// One row under a muscle: the exercise and its best e1RM.
    public struct Entry: Hashable, Sendable, Identifiable {
        public var exerciseID: UUID
        public var name: String
        public var e1rmKg: Double

        public var id: UUID { exerciseID }
    }

    /// Top `perMuscle` lifts for every primary mover with at least one, heaviest first; a lift
    /// without a positive e1RM never appears, so a never-trained muscle is simply absent.
    public static func top(lifts: [Lift], perMuscle: Int = 3) -> [Muscle: [Entry]] {
        var byMuscle: [Muscle: [Entry]] = [:]
        for lift in lifts where lift.e1rmKg > 0 {
            let entry = Entry(exerciseID: lift.exerciseID, name: lift.name, e1rmKg: lift.e1rmKg)
            for muscle in Set(lift.primary) { byMuscle[muscle, default: []].append(entry) }
        }
        return byMuscle.mapValues { entries in
            Array(entries.sorted { $0.e1rmKg == $1.e1rmKg ? $0.name < $1.name : $0.e1rmKg > $1.e1rmKg }
                .prefix(max(1, perMuscle)))
        }
    }

    /// Map tints: each muscle's best e1RM against the strongest muscle's, so the figure reads
    /// "where the big numbers are" at a glance. Absent for muscles with no lift.
    public static func mapIntensity(_ top: [Muscle: [Entry]]) -> [Muscle: Double] {
        let best = top.compactMapValues { $0.map(\.e1rmKg).max() }
        guard let ceiling = best.values.max(), ceiling > 0 else { return [:] }
        return best.mapValues { $0 == ceiling ? 1 : max(LibraryFacets.minimumLit, $0 / ceiling) }
    }
}
