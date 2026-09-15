import Foundation
import Testing

@testable import GymCore

@Suite("Ask about your training: answer grounding and question matching")
struct TrainingQuestionTests {
    @Test("number tokens are extracted as values")
    func numberExtraction() {
        #expect(CoachAnswerValidator.numbers(in: "82.5 kg × 8, 8, 7 on 12 Sep") == [82.5, 8, 8, 7, 12])
        #expect(CoachAnswerValidator.numbers(in: "no numbers here.").isEmpty)
        #expect(CoachAnswerValidator.numbers(in: "3.") == [3])
    }

    @Test("an answer may only repeat numbers a tool returned")
    func grounding() {
        let tools = [CoachToolResult(text: "Last bench: 82.5 kg × 8, 8, 7 (12 Sep). 3 sessions.")]
        #expect(CoachAnswerValidator.isGrounded(answer: "You benched 82.50 kg × 8", toolResults: tools))
        #expect(!CoachAnswerValidator.isGrounded(answer: "You benched 85 kg for 8 reps.", toolResults: tools)
        )
        #expect(!CoachAnswerValidator.isGrounded(answer: "That's 23 reps in total.", toolResults: tools))
        #expect(CoachAnswerValidator.isGrounded(answer: "Nice work on bench.", toolResults: tools))
    }

    private let names = ["Bench Press", "Squat", "Romanian Deadlift", "Lat Pulldown"]

    @Test("questions map onto the five tool queries")
    func matching() {
        #expect(CoachQuestionMatcher.query(for: "what did I bench last time", exerciseNames: names)
            == .lastSessions(exercise: "Bench Press"))
        #expect(CoachQuestionMatcher.query(for: "what's my squat PR", exerciseNames: names)
            == .personalRecords(exercise: "Squat"))
        #expect(CoachQuestionMatcher.query(for: "how many chest sets over 2 weeks", exerciseNames: names)
            == .weeklyVolume(muscle: "Chest", weeks: 2))
        #expect(CoachQuestionMatcher.query(for: "how consistent was I over 8 weeks", exerciseNames: names)
            == .adherence(weeks: 8))
        #expect(CoachQuestionMatcher.query(for: "are my hamstrings recovered", exerciseNames: names)
            == .recovery(muscle: "Hamstrings"))
        #expect(CoachQuestionMatcher.query(for: "how is my bench progressing", exerciseNames: names)
            == .lastSessions(exercise: "Bench Press"))
        #expect(CoachQuestionMatcher.query(for: "tell me a joke", exerciseNames: names) == nil)
    }
}
