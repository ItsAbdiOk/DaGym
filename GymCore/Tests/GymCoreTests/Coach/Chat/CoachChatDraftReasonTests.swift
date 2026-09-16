import Foundation
import Testing

@testable import GymCore

@Suite("CoachChatDraft: the per-exercise reason")
struct CoachChatDraftReasonTests {
    private static let benchID = UUID()
    private static let pullUpID = UUID()

    private let library = [
        SubstitutionCandidate(
            id: benchID, name: "Bench Press", primary: [.chest], equipment: "barbell", mechanic: "compound"
        ),
        SubstitutionCandidate(
            id: pullUpID, name: "Pull-Up", primary: [.lats], equipment: "bodyweight", mechanic: "compound"
        )
    ]
    private let gym = EquipmentAvailability(types: ["barbell", "bodyweight"])

    private func sets(_ count: Int, kg: Double? = 60) -> [CoachChatSetSpec] {
        Array(repeating: CoachChatSetSpec(targetReps: 8, targetWeightKg: kg), count: count)
    }

    private func spec(_ json: String) throws -> CoachChatExerciseSpec {
        try JSONDecoder().decode(CoachChatExerciseSpec.self, from: Data(json.utf8))
    }

    @Test("decodes from `reason`, `why` or `note`, and is absent when the model gave none")
    func decoding() throws {
        let base = "\"exercise_name\":\"Bench Press\",\"set_count\":3,\"target_reps\":8"
        #expect(try spec("{\(base)}").reason == nil)
        #expect(try spec("{\(base),\"reason\":\"Your best lift\"}").reason == "Your best lift")
        #expect(try spec("{\(base),\"why\":\"Chest is behind\"}").reason == "Chest is behind")
        #expect(try spec("{\(base),\"note\":\"Keep it\"}").reason == "Keep it")
        #expect(try spec("{\(base),\"sets\":[],\"reason\":\"Shorthand still\"}").reason == "Shorthand still")
    }

    @Test("validation trims and caps the reason and drops a blank one; it round-trips as `reason`")
    func validationAndRoundTrip() throws {
        let long = String(repeating: "r", count: 200)
        let draft = CoachChatDraft.routine(RoutineProposal(name: "A", exercises: [
            CoachChatExerciseSpec(exerciseName: "Bench Press", sets: sets(3), reason: " \(long) "),
            CoachChatExerciseSpec(exerciseName: "Pull-Up", sets: sets(3, kg: nil), reason: "   ")
        ]))
        guard case .routine(let validated) = try draft.validate(availability: gym, library: library).get()
        else { Issue.record("expected a routine"); return }
        #expect(validated.exercises[0].reason?.count == CoachChatDraft.Limits.maxReasonLength)
        #expect(validated.exercises[1].reason == nil)

        let encoded = try JSONEncoder().encode(validated.exercises[0])
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("\"reason\""))
        #expect(!json.contains("\"why\""))
        let decoded = try JSONDecoder().decode(CoachChatExerciseSpec.self, from: encoded)
        #expect(decoded.reason == validated.exercises[0].reason)
    }
}
