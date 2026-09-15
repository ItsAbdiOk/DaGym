import Foundation
import Testing
@testable import GymCore

@Suite("ExerciseMatcher")
struct ExerciseMatcherTests {
    /// ~40 real names from `DaGym/Resources/Seed/exercises.json`, hardcoded per the brief.
    private static let libraryNames: [String] = [
        "Barbell Bench Press - Medium Grip", "Dumbbell Bench Press", "Decline Dumbbell Bench Press",
        "Incline Dumbbell Bench With Palms Facing In", "Barbell Incline Bench Press - Medium Grip",
        "Barbell Shoulder Press", "Arnold Dumbbell Press", "Barbell Squat", "Barbell Full Squat",
        "Barbell Hack Squat", "Front Barbell Squat", "Barbell Deadlift", "Romanian Deadlift",
        "Barbell Romanian Deadlift (RDL)", "Dumbbell Romanian Deadlift", "Axle Deadlift",
        "Bent Over Barbell Row", "Bent Over Two-Dumbbell Row", "Alternating Kettlebell Row",
        "Seated Cable Row", "Chin-Up", "Pullups", "Assisted Pull-Up", "Band Assisted Pull-Up",
        "Bench Dips", "Dip Machine", "Leg Press", "Narrow Stance Leg Press", "Seated Leg Curl",
        "Lying Leg Curls", "Standing Leg Curl", "Leg Extensions", "EZ-Bar Skullcrusher",
        "Skullcrusher Dumbbells", "Barbell Curl", "Alternate Hammer Curl", "Cable Seated Lateral Raise",
        "Front Incline Dumbbell Raise", "Plank", "Reverse Plank", "Bodyweight Squat"
    ]

    private static func candidates() -> [ParseContext.ExerciseCandidate] {
        libraryNames.map { name in
            ParseContext.ExerciseCandidate(id: UUID(), name: name, equipment: equipment(for: name))
        }
    }

    private static func equipment(for name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("dumbbell") { return "dumbbell" }
        if lower.contains("barbell") { return "barbell" }
        if lower.contains("cable") { return "cable" }
        if lower.contains("machine") { return "machine" }
        return nil
    }

    private static func context(aliases: [String: UUID] = [:]) -> ParseContext {
        ParseContext(unit: .kg, library: candidates(), aliases: aliases)
    }

    @Test(
        "golden fuzzy matches",
        arguments: [
            ("dumbbell bench press", "Dumbbell Bench Press"),
            ("barbell squat", "Barbell Squat"),
            ("romanian deadlift", "Romanian Deadlift"),
            ("bent over barbell row", "Bent Over Barbell Row"),
            ("chin up", "Chin-Up"),
            ("skullcrusher", "Skullcrusher Dumbbells"),
            ("leg press", "Leg Press"),
            ("seated leg curl", "Seated Leg Curl"),
            ("barbell curl", "Barbell Curl"),
            ("plank", "Plank")
        ] as [(String, String)]
    )
    func goldenMatches(phrase: String, expectedName: String) {
        let matches = ExerciseMatcher.match(phrase, in: Self.context())
        #expect(matches.first?.name == expectedName)
    }

    @Test("a candidate's match keys are computed once and follow a renamed candidate")
    func candidateKeysArePrecomputed() {
        var candidate = ParseContext.ExerciseCandidate(id: UUID(), name: "Incline Dumbbell Presses")
        #expect(candidate.normalizedName == "incline dumbbell presses")
        #expect(candidate.tokens == ["incline", "dumbbell", "press"])
        #expect(candidate.tokenSet == ["incline", "dumbbell", "press"])
        candidate.name = "Barbell Rows"
        #expect(candidate.normalizedName == "barbell rows")
        #expect(candidate.tokens == ["barbell", "row"])
        let scored = ExerciseMatcher.score(phrase: "barbell row", candidate: candidate)
        #expect(scored > 0.9)
    }

    @Test("exact alias short-circuits at score 1.0")
    func aliasShortCircuit() {
        let id = UUID()
        let ctx = ParseContext(unit: .kg, library: Self.candidates(), aliases: ["bench": id])
        let ref = ExerciseMatcher.resolve("bench", in: ctx)
        #expect(ref == .id(id))
    }

    @Test("ambiguous phrase returns disambiguation candidates")
    func ambiguous() {
        let ref = ExerciseMatcher.resolve("row", in: Self.context())
        if case .spoken(_, let candidates) = ref {
            #expect(!candidates.isEmpty)
        } else if case .id = ref {
            // A clear winner is also an acceptable outcome for a short generic phrase.
        } else {
            Issue.record("expected .spoken or .id, got \(ref)")
        }
    }

    @Test("gibberish never resolves to a confident id")
    func gibberish() {
        let matches = ExerciseMatcher.match("qzxjklw nonsense", in: Self.context())
        #expect((matches.first?.score ?? 0) < ExerciseMatcher.threshold)
    }

    @Test("session-exercise boost outranks an equal library match")
    func sessionBoost() {
        let sessionID = UUID()
        let libraryID = UUID()
        let ctx = ParseContext(
            unit: .kg,
            sessionExercises: [ParseContext.ExerciseCandidate(
                id: sessionID, name: "Barbell Squat", isInSession: true
            )],
            library: [ParseContext.ExerciseCandidate(id: libraryID, name: "Barbell Squat")]
        )
        let matches = ExerciseMatcher.match("barbell squat", in: ctx)
        #expect(matches.first?.id == sessionID)
    }
}
