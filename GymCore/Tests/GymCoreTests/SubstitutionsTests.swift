import Foundation
import Testing
@testable import GymCore

@Suite("Rule-based substitutions")
struct SubstitutionsTests {
    private let bench = SubstitutionCandidate(
        id: UUID(), name: "Barbell Bench Press", primary: [.chest], secondary: [.triceps, .delts],
        equipment: "barbell", mechanic: "compound"
    )
    private let inclineDB = SubstitutionCandidate(
        id: UUID(), name: "Incline Dumbbell Press", primary: [.chest], secondary: [.triceps, .delts],
        equipment: "dumbbell", mechanic: "compound"
    )
    private let cableFly = SubstitutionCandidate(
        id: UUID(), name: "Cable Fly", primary: [.chest], secondary: [], equipment: "cable",
        mechanic: "isolation"
    )
    private let machineChest = SubstitutionCandidate(
        id: UUID(), name: "Chest Press Machine", primary: [.chest], secondary: [.triceps],
        equipment: "machine", mechanic: "compound"
    )
    private let legPress = SubstitutionCandidate(
        id: UUID(), name: "Leg Press", primary: [.quads], secondary: [.glutes], equipment: "machine",
        mechanic: "compound"
    )

    private var library: [SubstitutionCandidate] {
        [bench, inclineDB, cableFly, machineChest, legPress]
    }

    @Test("a station the profile lacks is never offered, and a taken machine is not offered back")
    func stationFiltering() {
        let pecDeck = SubstitutionCandidate(
            id: UUID(), name: "Pec Deck", primary: [.chest], secondary: [], equipment: "machine",
            mechanic: "isolation", machine: "pecDeck"
        )
        let chestPress = SubstitutionCandidate(
            id: UUID(), name: "Chest Press Machine", primary: [.chest], secondary: [.triceps],
            equipment: "machine", mechanic: "compound", machine: "chestPressMachine"
        )
        let crossover = SubstitutionCandidate(
            id: UUID(), name: "Cable Crossover", primary: [.chest], secondary: [], equipment: "cable",
            mechanic: "isolation", machine: "cableStation"
        )
        let gym = EquipmentAvailability(
            types: ["machine", "cable", "dumbbell"], restrictsMachines: true,
            machines: [.chestPressMachine, .latPulldown]
        )
        let names = Substitutions.candidates(
            for: bench, reason: .shortOnTime, library: [pecDeck, chestPress, crossover, inclineDB],
            availability: gym, recoveryMap: [:]
        ).map(\.candidate.name)
        #expect(names.contains("Chest Press Machine"))
        #expect(names.contains("Incline Dumbbell Press"))
        #expect(!names.contains("Pec Deck"))
        #expect(!names.contains("Cable Crossover"))

        // Swapping out a taken lat pulldown must not suggest another lat pulldown seat.
        let wide = SubstitutionCandidate(
            id: UUID(), name: "Wide-Grip Lat Pulldown", primary: [.lats], secondary: [],
            equipment: "cable", mechanic: "compound", machine: "latPulldown"
        )
        let close = SubstitutionCandidate(
            id: UUID(), name: "Close-Grip Lat Pulldown", primary: [.lats], secondary: [],
            equipment: "cable", mechanic: "compound", machine: "latPulldown"
        )
        let straightArm = SubstitutionCandidate(
            id: UUID(), name: "Straight-Arm Pulldown", primary: [.lats], secondary: [],
            equipment: "cable", mechanic: "isolation", machine: "cableStation"
        )
        let cables = EquipmentAvailability(types: ["cable"])
        let swaps = Substitutions.candidates(
            for: wide, reason: .machineTaken, library: [close, straightArm], availability: cables,
            recoveryMap: [:]
        ).map(\.candidate.name)
        #expect(swaps == ["Straight-Arm Pulldown"])
    }

    @Test("only equipment the user actually has comes back")
    func equipmentFiltering() {
        let results = Substitutions.candidates(
            for: bench, reason: .machineTaken, library: library, available: ["dumbbell", "cable"],
            recoveryMap: [:]
        )
        #expect(results.allSatisfy { ["dumbbell", "cable"].contains($0.candidate.equipment) })
        #expect(!results.contains { $0.candidate.equipment == "machine" })
    }

    @Test(".machineTaken excludes machines even when one is in the available set")
    func machineTakenExcludesMachines() {
        let results = Substitutions.candidates(
            for: bench, reason: .machineTaken, library: library,
            available: ["dumbbell", "cable", "machine"], recoveryMap: [:]
        )
        #expect(!results.contains { $0.candidate.equipment == "machine" })
    }

    @Test(".noBarbell excludes barbell candidates even when barbell is available")
    func noBarbellExcludesBarbell() {
        let results = Substitutions.candidates(
            for: cableFly, reason: .noBarbell, library: library,
            available: ["barbell", "dumbbell", "cable", "machine"], recoveryMap: [:]
        )
        #expect(!results.contains { $0.candidate.equipment == "barbell" })
    }

    @Test("only exercises sharing a primary muscle are returned")
    func requiresSharedPrimaryMuscle() {
        let results = Substitutions.candidates(
            for: bench, reason: .machineTaken, library: library,
            available: ["dumbbell", "cable", "machine"], recoveryMap: [:]
        )
        #expect(!results.contains { $0.candidate.id == legPress.id })
    }

    @Test("shoulder-hurts penalises delt-heavy candidates and favors isolation/machine")
    func shoulderRule() {
        let results = Substitutions.candidates(
            for: bench, reason: .shoulderHurts, library: library,
            available: ["dumbbell", "cable", "machine"], recoveryMap: [:]
        )
        let ids = results.map(\.candidate.id)
        // Cable fly (isolation, no delts) should outrank incline DB (compound, hits delts).
        guard let flyIndex = ids.firstIndex(of: cableFly.id),
              let inclineIndex = ids.firstIndex(of: inclineDB.id) else {
            Issue.record("expected both cable fly and incline DB in the results")
            return
        }
        #expect(flyIndex < inclineIndex)
    }

    @Test(".painArea(.delts) behaves the same as .shoulderHurts")
    func painAreaMatchesShoulderShorthand() {
        let byArea = Substitutions.candidates(
            for: bench, reason: .painArea(.delts), library: library,
            available: ["dumbbell", "cable", "machine"], recoveryMap: [:]
        )
        let byShorthand = Substitutions.candidates(
            for: bench, reason: .shoulderHurts, library: library,
            available: ["dumbbell", "cable", "machine"], recoveryMap: [:]
        )
        #expect(byArea.map(\.candidate.id) == byShorthand.map(\.candidate.id))
    }

    @Test("short-on-time favors compound over isolation")
    func shortOnTimeFavorsCompound() {
        let results = Substitutions.candidates(
            for: bench, reason: .shortOnTime, library: library,
            available: ["dumbbell", "cable", "machine"], recoveryMap: [:]
        )
        let ids = results.map(\.candidate.id)
        guard let inclineIndex = ids.firstIndex(of: inclineDB.id),
              let flyIndex = ids.firstIndex(of: cableFly.id) else {
            Issue.record("expected both incline DB and cable fly in the results")
            return
        }
        #expect(inclineIndex < flyIndex)
    }

    @Test("a fatigued shared muscle reduces score enough to reorder candidates")
    func recoveryPenalty() {
        let squat = SubstitutionCandidate(
            id: UUID(), name: "Back Squat", primary: [.quads], secondary: [.hams],
            equipment: "barbell", mechanic: "compound"
        )
        // More secondary overlap than hackSquat, so it wins while nothing is fatigued.
        let legPress = SubstitutionCandidate(
            id: UUID(), name: "Leg Press", primary: [.quads], secondary: [.hams, .glutes],
            equipment: "machine", mechanic: "compound"
        )
        let hackSquat = SubstitutionCandidate(
            id: UUID(), name: "Hack Squat", primary: [.quads], secondary: [], equipment: "machine",
            mechanic: "compound"
        )

        let fresh = Substitutions.candidates(
            for: squat, reason: .noBarbell, library: [legPress, hackSquat], available: ["machine"],
            recoveryMap: [:]
        )
        #expect(fresh.first?.candidate.id == legPress.id)

        // Hamstrings (shared by squat and leg press, but not hack squat) are heavily spent —
        // leg press should drop behind hack squat once that penalty is applied.
        let fatigued = Substitutions.candidates(
            for: squat, reason: .noBarbell, library: [legPress, hackSquat], available: ["machine"],
            recoveryMap: [.hams: 0.9]
        )
        #expect(fatigued.first?.candidate.id == hackSquat.id)
    }

    @Test("results are capped at 3 and ordered deterministically for equal scores")
    func topThreeDeterministicOrder() {
        let identical = (0..<5).map { index in
            SubstitutionCandidate(
                id: UUID(), name: "Candidate \(index)", primary: [.chest], equipment: "dumbbell",
                mechanic: "compound"
            )
        }
        let results = Substitutions.candidates(
            for: bench, reason: .machineTaken, library: identical, available: ["dumbbell"],
            recoveryMap: [:]
        )
        #expect(results.count == 3)
        #expect(results.map(\.candidate.name) == ["Candidate 0", "Candidate 1", "Candidate 2"])

        // Running it again produces the exact same order.
        let again = Substitutions.candidates(
            for: bench, reason: .machineTaken, library: identical, available: ["dumbbell"],
            recoveryMap: [:]
        )
        #expect(again.map(\.candidate.id) == results.map(\.candidate.id))
    }

    @Test("each result carries a one-line why")
    func hasWhyText() {
        let results = Substitutions.candidates(
            for: bench, reason: .machineTaken, library: library,
            available: ["dumbbell", "cable"], recoveryMap: [:]
        )
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { !$0.reason.isEmpty })
    }
}
