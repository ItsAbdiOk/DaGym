import Foundation
import GymCore
import Testing

@testable import DaGym

/// Rule-picker default increment by body region and unit (docs/reviews/opengym/engine.md rec 5).
@Suite("Rule picker default increment")
struct ParityWorkoutIncrementTests {
    private let squat = ExerciseInfo(name: "Squat", primary: [.quads, .glutes], equipment: "Barbell")
    private let bench = ExerciseInfo(name: "Bench Press", primary: [.chest], equipment: "Barbell")
    private let routineRule = ProgressionRule.doubleProgression(low: 6, high: 8, incrementKg: 1.25)

    @Test("a lower-body lift defaults to 5 kg, an upper-body one to 2.5 kg")
    func kgDefaultsByRegion() {
        #expect(RuleState.defaultIncrementKg(for: squat, unit: .kg) == 5)
        #expect(RuleState.defaultIncrementKg(for: bench, unit: .kg) == 2.5)
    }

    @Test("a lb lifter gets round 10 lb / 5 lb increments so the card reads +10 lb")
    func lbDefaultsRoundInPounds() {
        let deadlift = ExerciseInfo(name: "Deadlift", primary: [.hams], equipment: "Barbell")
        let state = RuleState.exerciseOverride(of: .linear(incrementKg: 2.5), for: deadlift, unit: .lb)
        #expect(abs(state.incrementKg - 4.536) < 0.001)
        #expect(state.rule.explanation(unit: .lb).contains("Adds 10 lb"))
        #expect(WeightUnit.lb.format(kg: RuleState.defaultIncrementKg(for: bench, unit: .lb)) == "5")
    }

    @Test("an override keeps the routine rule's kind and rep range, only the increment resets")
    func overrideKeepsKind() {
        let state = RuleState.exerciseOverride(of: routineRule, for: squat, unit: .kg)
        #expect(state.kind == .doubleProgression)
        #expect(state.repLow == 6 && state.repHigh == 8)
        #expect(state.rule == .doubleProgression(low: 6, high: 8, incrementKg: 5))
    }
}
