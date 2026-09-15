import Foundation
import Testing
@testable import GymCore

@Suite("Machine taxonomy")
struct MachineTests {
    @Test("every station has a unique display name and belongs to a kind that has stations")
    func namesAreUniqueAndTyped() {
        let names = Machine.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        for machine in Machine.allCases {
            #expect(Machine.equipmentTypes.contains(machine.equipmentType), "\(machine) has no kind")
        }
    }

    @Test("aliases are non-empty, never repeat the canonical name, and are unique across stations")
    func aliasesAreClean() {
        var seen: [String: Machine] = [:]
        for machine in Machine.allCases {
            #expect(!machine.aliases.isEmpty, "\(machine) has no aliases")
            for alias in machine.aliases {
                let key = alias.lowercased()
                #expect(key != machine.displayName.lowercased(), "\(machine) repeats its own name")
                let other = seen[key].map { "\($0)" } ?? ""
                #expect(seen[key] == nil, "'\(alias)' names both \(machine) and \(other)")
                seen[key] = machine
            }
        }
    }

    @Test("search matches the canonical name and every alias, case- and accent-insensitively")
    func searchMatchesAliases() {
        #expect(Machine.search("gravitron") == [.assistedDipPullUp])
        #expect(Machine.search("PEC FLY") == [.pecDeck])
        #expect(Machine.search("45° leg") == [.legPress])
        #expect(Machine.search("45 leg").isEmpty)
        #expect(Machine.search("stairmaster") == [.stairClimber])
        #expect(Machine.search("  ") == Machine.allCases)
        #expect(Machine.search("row").contains(.rowMachine))
        #expect(Machine.search("row").contains(.seatedRowMachine))
        #expect(Machine.search("row").contains(.rower))
    }

    @Test("the brand labels a PureGym floor prints resolve to one station each")
    func brandLabelsResolve() {
        #expect(Machine.search("iso-lateral row") == [.rowMachine])
        #expect(Machine.search("iso-lateral chest press") == [.chestPressMachine])
        #expect(Machine.search("diverging seated row") == [.rowMachine])
        #expect(Machine.search("multi press") == [.smithMachine])
        #expect(Machine.search("lat pull down") == [.latPulldown])
        #expect(Machine.search("cable pulley") == [.cableStation])
        #expect(Machine.search("dip machine").contains(.seatedDipMachine))
        #expect(!Machine.search("dip machine").contains(.tricepsExtensionMachine))
        #expect(Machine.search("GHD") == [.gluteHamDeveloper])
        #expect(Machine.search("machine lateral raise") == [.lateralRaiseMachine])
        #expect(Machine.search("nautilus pullover") == [.pulloverMachine])
        #expect(Machine.search("skierg") == [.skiErg])
        #expect(Machine.skiErg.isCardio)
        #expect(Machine.seatedDipMachine.equipmentType == "machine")
    }

    @Test("stations grouped by kind cover every case exactly once and raw values round-trip")
    func groupingIsAPartition() {
        let grouped = Machine.equipmentTypes.flatMap(Machine.machines(ofType:))
        #expect(grouped.count == Machine.allCases.count)
        #expect(Set(grouped) == Set(Machine.allCases))
        for machine in Machine.allCases {
            #expect(Machine(rawValue: machine.rawValue) == machine)
        }
        #expect(Machine.allCases.filter(\.isCardio).allSatisfy { $0.equipmentType == "machine" })
    }
}

@Suite("Equipment availability")
struct EquipmentAvailabilityTests {
    private let allTypes = [
        "barbell", "dumbbell", "bodyweight", "cable", "machine", "kettlebell", "bands", "ezBar", "other"
    ]

    @Test("kind off hides; kind on with no station list allows every station of that kind")
    func typeGate() {
        let noMachines = EquipmentAvailability(types: ["barbell", "cable"])
        #expect(noMachines.verdict(equipment: "machine", machine: "legPress") == .missingType("machine"))
        #expect(noMachines.allows(equipment: "cable", machine: "latPulldown"))
        #expect(noMachines.allows(equipment: "cable", machine: nil))
        #expect(noMachines.allows(equipment: "barbell", machine: nil))

        let unrestricted = EquipmentAvailability(types: ["machine"])
        for machine in Machine.machines(ofType: "machine") {
            #expect(unrestricted.allows(equipment: "machine", machine: machine.rawValue))
        }
    }

    @Test("kind on with a station list allows only the listed stations; untagged rows still pass")
    func machineGate() {
        let gym = EquipmentAvailability(
            types: ["machine", "cable"], restrictsMachines: true, machines: [.legPress, .cableStation]
        )
        #expect(gym.allows(equipment: "machine", machine: "legPress"))
        #expect(gym.verdict(equipment: "machine", machine: "pecDeck") == .missingMachine(.pecDeck))
        #expect(gym.verdict(equipment: "cable", machine: "latPulldown") == .missingMachine(.latPulldown))
        #expect(gym.allows(equipment: "cable", machine: "cableStation"))
        // No specific station: any machine of the kind will do.
        #expect(gym.allows(equipment: "machine", machine: nil))
        // An unknown station name (newer taxonomy) never hides anything.
        #expect(gym.allows(equipment: "machine", machine: "hoverboard"))
    }

    @Test("a station whose own kind is off is missing even when the row's kind is on")
    func stationKindMustBeOn() {
        let home = EquipmentAvailability(types: ["other", "dumbbell"])
        // "Smith Press" is filed under "other" in the seed but needs the Smith machine.
        #expect(home.verdict(equipment: "other", machine: "smithMachine") == .missingMachine(.smithMachine))
    }

    @Test("restricting to no stations at all is a real answer, not 'all'")
    func noneIsNotAll() {
        let none = EquipmentAvailability(types: ["bodyweight"], restrictsMachines: true, machines: [])
        #expect(!none.allows(equipment: "bodyweight", machine: "pullUpBar"))
        #expect(none.allows(equipment: "bodyweight", machine: nil))
        #expect(none.offeredMachines.isEmpty)
    }

    @Test("restricts(allTypes:) is false only for every kind and every station")
    func restrictsLibrary() {
        let everything = EquipmentAvailability(types: Set(allTypes))
        #expect(!everything.restricts(allTypes: allTypes))
        let listed = EquipmentAvailability(
            types: Set(allTypes), restrictsMachines: true, machines: Set(Machine.allCases)
        )
        #expect(!listed.restricts(allTypes: allTypes))
        var short = listed
        short.machines.remove(.pecDeck)
        #expect(short.restricts(allTypes: allTypes))
        #expect(EquipmentAvailability(types: ["dumbbell"]).restricts(allTypes: allTypes))
    }

    @Test("hidden counts and needs split by kind versus station, in first-use order, once each")
    func countsAndNeeds() {
        let gym = EquipmentAvailability(
            types: ["barbell", "machine"], restrictsMachines: true, machines: [.legPress]
        )
        let routine: [(equipment: String, machine: String?)] = [
            ("barbell", nil), ("machine", "pecDeck"), ("dumbbell", nil), ("machine", "legPress"),
            ("machine", "pecDeck"), ("cable", "cableStation"), ("machine", "legCurl")
        ]
        let counts = gym.hiddenCounts(of: routine)
        #expect(counts == HiddenCounts(byType: 2, byMachine: 3))
        #expect(counts.total == 5)
        let needs = gym.missing(from: routine)
        #expect(needs.types == ["dumbbell", "cable"])
        #expect(needs.machines == [.pecDeck, .legCurl])
        #expect(gym.missing(from: [("barbell", nil)]).isEmpty)
    }

    @Test("subtracting kinds keeps the station list")
    func subtracting() {
        let gym = EquipmentAvailability(
            types: ["barbell", "machine"], restrictsMachines: true, machines: [.legPress]
        )
        let noBarbell = gym.subtracting(types: ["barbell"])
        #expect(noBarbell.types == ["machine"])
        #expect(noBarbell.machines == [.legPress])
        #expect(noBarbell.restrictsMachines)
    }
}
