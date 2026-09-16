import Foundation
import Testing

@testable import GymCore

@Suite("CoachChatSaveText: which exercises a reply names, and what a note or memory keeps")
struct CoachChatSaveTextTests {
    private let bench = SubstitutionCandidate(
        id: UUID(), name: "Bench Press", primary: [.chest], equipment: "barbell", mechanic: "compound"
    )
    private let incline = SubstitutionCandidate(
        id: UUID(), name: "Incline Bench Press", primary: [.chest], equipment: "barbell", mechanic: "compound"
    )
    private let row = SubstitutionCandidate(
        id: UUID(), name: "Row", primary: [.lats], equipment: "cable", mechanic: "compound"
    )
    private let legPress = SubstitutionCandidate(
        id: UUID(), name: "Leg Press", primary: [.quads], equipment: "machine", mechanic: "compound",
        machine: "legPress"
    )
    private var library: [SubstitutionCandidate] { [bench, incline, row, legPress] }

    private func named(_ text: String) -> [String] {
        CoachChatSaveText.exercisesNamed(in: text, library: library).map(\.name)
    }

    @Test("two exercises named come back in order of mention, each once, case-insensitively")
    func twoExercises() {
        let text = "Keep the leg press light this week. Your bench press is fine; bench press again Friday."
        let named = CoachChatSaveText.exercisesNamed(in: text, library: library)
        #expect(named.map(\.name) == ["Leg Press", "Bench Press"])
    }

    @Test("a shorter name inside a longer match does not count, and only whole words match")
    func longestMatchWins() {
        #expect(named("Add Incline Bench Press after rowing.") == ["Incline Bench Press"])
        #expect(named("Nothing named here.").isEmpty)
        #expect(named("One row, then rest.") == ["Row"])
    }

    @Test("the list is capped and an unavailable machine's exercise is still offered")
    func capAndEquipment() {
        let text = "Leg Press, Row, Bench Press and Incline Bench Press."
        let capped = CoachChatSaveText.exercisesNamed(in: text, library: library, limit: 2)
        #expect(capped.map(\.name) == ["Leg Press", "Row"])
        let offered = CoachChatSaveText.exercisesNamed(in: "Skip the Leg Press.", library: library)
        #expect(offered.first?.id == legPress.id)
    }

    @Test("an exercise note is prefixed, collapsed and cut at 300 characters")
    func exerciseNote() {
        #expect(CoachChatSaveText.exerciseNote("  Pause  each\nrep. ") == "Coach: Pause each rep.")
        #expect(CoachChatSaveText.exerciseNote(" \n ") == nil)
        let long = String(repeating: "x", count: 400)
        let note = CoachChatSaveText.exerciseNote(long) ?? ""
        #expect(note.count == CoachChatSaveText.maxExerciseNoteLength)
        #expect(note.hasSuffix("…"))
        #expect(note.hasPrefix("Coach: "))
    }

    @Test("the memory gist is the first sentences that fit 200 characters")
    func memoryGist() {
        let text = "Your bench stalled at 80 kg! Deload 10% next week. Then build back up over four weeks."
        #expect(CoachChatSaveText.memoryGist(text) == text)
        let second = String(repeating: "b", count: 150) + "."
        let third = String(repeating: "c", count: 150) + "."
        let gist = CoachChatSaveText.memoryGist("First point. " + second + " " + third)
        #expect(gist == "First point. " + second)
        let runOn = String(repeating: "a", count: 250)
        #expect(CoachChatSaveText.memoryGist(runOn)?.count == CoachMemoryValidation.maxTextLength)
        #expect(CoachChatSaveText.memoryGist("   ") == nil)
    }
}
