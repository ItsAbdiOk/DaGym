import Foundation
import Testing

@testable import GymCore

@Suite("CoachChatDraft: fuzzy exercise names")
struct CoachChatDraftFuzzyNameTests {
    private static let benchID = UUID()
    private static let legPressID = UUID()
    private static let rowID = UUID()
    private static let pullUpID = UUID()

    private let library = [
        SubstitutionCandidate(
            id: benchID, name: "Bench Press", primary: [.chest], equipment: "barbell", mechanic: "compound"
        ),
        SubstitutionCandidate(
            id: legPressID, name: "Leg Press", primary: [.quads], equipment: "machine", mechanic: "compound",
            machine: Machine.legPress.rawValue
        ),
        SubstitutionCandidate(
            id: rowID, name: "Cable Row", primary: [.lats], equipment: "cable", mechanic: "compound",
            machine: Machine.seatedRowMachine.rawValue
        ),
        SubstitutionCandidate(
            id: pullUpID, name: "Pull-Up", primary: [.lats], equipment: "bodyweight", mechanic: "compound",
            machine: Machine.pullUpBar.rawValue
        )
    ]

    /// Barbell, cable and bodyweight, but no machines at all and only a seated row among stations.
    private let homeGym = EquipmentAvailability(
        types: ["barbell", "cable", "bodyweight"], restrictsMachines: true, machines: [.seatedRowMachine]
    )
    private let fullGym = EquipmentAvailability(types: ["barbell", "machine", "cable", "bodyweight"])

    private func sets(_ count: Int, reps: Int = 8, kg: Double? = 60) -> [CoachChatSetSpec] {
        Array(repeating: CoachChatSetSpec(targetReps: reps, targetWeightKg: kg), count: count)
    }

    @Test("a partial or abbreviated name resolves to the closest library exercise")
    func fuzzyNames() {
        let wider = library + [
            SubstitutionCandidate(
                id: UUID(), name: "Wide-Grip Lat Pulldown", primary: [.lats], equipment: "cable",
                mechanic: "compound"
            ),
            SubstitutionCandidate(
                id: UUID(), name: "Close-Grip Lat Pulldown", primary: [.lats], equipment: "cable",
                mechanic: "compound"
            ),
            SubstitutionCandidate(
                id: UUID(), name: "Dumbbell Bench Press", primary: [.chest], equipment: "dumbbell",
                mechanic: "compound"
            )
        ]
        let draft = CoachChatDraft.routine(RoutineProposal(
            name: "Pull",
            exercises: [
                CoachChatExerciseSpec(exerciseName: "Lat Pulldown", sets: sets(3)),
                CoachChatExerciseSpec(exerciseName: "DB bench press", sets: sets(3)),
                CoachChatExerciseSpec(exerciseName: "bench press (barbell)", sets: sets(3))
            ]
        ))
        let gym = EquipmentAvailability(types: ["barbell", "dumbbell", "machine", "cable", "bodyweight"])
        let result = draft.validate(availability: gym, library: wider)
        guard case .success(.routine(let routine)) = result else {
            if case .failure(let rejection) = result { Issue.record("\(rejection.reasons)") }
            return
        }
        let names = routine.exercises.map(\.exerciseName)
        // Two pulldowns match; the shorter/allowed one wins. Abbreviations expand. Qualifiers drop.
        #expect(names == ["Wide-Grip Lat Pulldown", "Dumbbell Bench Press", "Bench Press"])

        var reasons: [String] = []
        let resolver = CoachChatExerciseResolver(library: wider, availability: gym)
        #expect(resolver.resolve(id: nil, name: "Pendlay Row", reasons: &reasons) == nil)
        #expect(reasons.first?.contains("closest in the library: Cable Row") == true)
    }

}
