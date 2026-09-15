import Foundation

/// What one equipment profile lets an exercise use: the equipment kinds that are ticked, and —
/// when the lifter has narrowed a kind down to specific stations — which `Machine`s are there.
/// One value, derived from the profile once, that the library, the picker, the routine
/// warning, the substitution engine and the program generator all consult, so "everything I
/// pick will work" holds the same way everywhere.
///
/// `restrictsMachines == false` (the default, and every profile that predates stations) means
/// "every station of the ticked kinds" — the behaviour the app had before stations existed.
/// `restrictsMachines == true` with an empty `machines` set is a real answer too: "none of the
/// stations" (a home gym with dumbbells and no pull-up bar).
public struct EquipmentAvailability: Hashable, Sendable {
    /// Equipment kinds ("barbell", "machine", "cable", …) that are ticked.
    public var types: Set<String>
    public var restrictsMachines: Bool
    /// Stations that are there. Only consulted when `restrictsMachines` is true.
    public var machines: Set<Machine>

    public init(types: Set<String>, restrictsMachines: Bool = false, machines: Set<Machine> = []) {
        self.types = types
        self.restrictsMachines = restrictsMachines
        self.machines = machines
    }

    /// Why an exercise is (or isn't) doable with this equipment.
    public enum Verdict: Hashable, Sendable {
        case allowed
        /// The exercise's equipment kind isn't ticked.
        case missingType(String)
        /// The kind is ticked, but the station this exercise needs isn't there — or the station's
        /// own kind isn't ticked (a Smith-machine row filed under "other" still needs the machine).
        case missingMachine(Machine)
    }

    public func verdict(equipment: String, machine: String?) -> Verdict {
        guard types.contains(equipment) else { return .missingType(equipment) }
        // An unknown station name (a future taxonomy case on an older build) restricts nothing.
        guard let raw = machine, let station = Machine(rawValue: raw) else { return .allowed }
        guard types.contains(station.equipmentType) else { return .missingMachine(station) }
        if restrictsMachines, !machines.contains(station) { return .missingMachine(station) }
        return .allowed
    }

    /// True when an exercise of `equipment` (optionally needing `machine`) can be done here.
    public func allows(equipment: String, machine: String?) -> Bool {
        verdict(equipment: equipment, machine: machine) == .allowed
    }

    public func allows(_ candidate: SubstitutionCandidate) -> Bool {
        allows(equipment: candidate.equipment, machine: candidate.machine)
    }

    /// The stations this profile offers, given its kinds: everything of a ticked kind when it
    /// doesn't restrict, else the listed ones (of ticked kinds only).
    public var offeredMachines: Set<Machine> {
        let ofTickedTypes = Set(Machine.allCases.filter { types.contains($0.equipmentType) })
        return restrictsMachines ? machines.intersection(ofTickedTypes) : ofTickedTypes
    }

    /// Whether filtering by this value would hide anything, given every kind the app knows.
    /// False for the seeded "Gym" (every kind, every station), so the library can skip its
    /// "Showing what's in …" banner.
    public func restricts(allTypes: [String]) -> Bool {
        !allTypes.allSatisfy(types.contains) || offeredMachines.count < Machine.allCases.count
    }

    /// The same availability with `excluded` kinds taken away — the program questionnaire's
    /// "leave out equipment" applied on top of the profile.
    public func subtracting(types excluded: Set<String>) -> EquipmentAvailability {
        var copy = self
        copy.types.subtract(excluded)
        return copy
    }

    /// How many of `items` this value hides, split by the reason, for the library banner
    /// ("12 hidden by equipment, 3 by machine").
    public func hiddenCounts(of items: [(equipment: String, machine: String?)]) -> HiddenCounts {
        var counts = HiddenCounts()
        for item in items {
            switch verdict(equipment: item.equipment, machine: item.machine) {
            case .allowed: continue
            case .missingType: counts.byType += 1
            case .missingMachine: counts.byMachine += 1
            }
        }
        return counts
    }

    /// The kinds and stations `items` (a routine's exercises, in order) need that this value
    /// lacks — first-use order, no repeats — for "Needs: barbell, leg press".
    public func missing(from items: [(equipment: String, machine: String?)]) -> EquipmentNeeds {
        var needs = EquipmentNeeds()
        for item in items {
            switch verdict(equipment: item.equipment, machine: item.machine) {
            case .allowed: continue
            case .missingType(let type):
                if !needs.types.contains(type) { needs.types.append(type) }
            case .missingMachine(let machine):
                if !needs.machines.contains(machine) { needs.machines.append(machine) }
            }
        }
        return needs
    }
}

public struct HiddenCounts: Hashable, Sendable {
    public var byType = 0
    public var byMachine = 0

    public init(byType: Int = 0, byMachine: Int = 0) {
        self.byType = byType
        self.byMachine = byMachine
    }

    public var total: Int { byType + byMachine }
}

/// What a routine needs that the profile lacks: equipment kinds first, then stations.
public struct EquipmentNeeds: Hashable, Sendable {
    public var types: [String] = []
    public var machines: [Machine] = []

    public init(types: [String] = [], machines: [Machine] = []) {
        self.types = types
        self.machines = machines
    }

    public var isEmpty: Bool { types.isEmpty && machines.isEmpty }
}
