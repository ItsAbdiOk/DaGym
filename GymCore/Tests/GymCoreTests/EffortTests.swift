import Testing
@testable import GymCore

@Suite("Effort")
struct EffortTests {
    @Test("RPE 8 and RIR 2 are the same set")
    func rpeRir() {
        #expect(Effort(rpe: 8) == Effort(rir: 2))
        #expect(Effort(rpe: 8).displayValue(scale: .rir) == "2")
        #expect(Effort(rir: 2).displayValue(scale: .rpe) == "8")
    }

    @Test("plain-language line follows the level")
    func language() {
        #expect(Effort(rpe: 8).plainLanguage == "Hard — 2 reps in the tank")
        #expect(Effort(rpe: 10).plainLanguage == "Nothing left")
        #expect(Effort(rpe: 9).plainLanguage == "1 rep left")
    }

    @Test("clamped to 5…10")
    func clamp() {
        #expect(Effort(rpe: 2).rpe == 5)
        #expect(Effort(rpe: 12).rpe == 10)
    }
}
