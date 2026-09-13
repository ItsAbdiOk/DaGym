import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — linear + AMRAP")
struct ProgressionEngineAMRAPTests {
    private let rule = ProgressionRule.linearAMRAP(incrementKg: 2.5)
    private let planned = [
        PlannedSetSpec(kind: .working, targetReps: 8),
        PlannedSetSpec(kind: .working, targetReps: 8),
        PlannedSetSpec(kind: .amrap, targetReps: 8)
    ]

    private func entry(amrapReps: Int, weightKg: Double = 100) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            date: .now,
            sets: [
                HistorySet(kind: .working, weightKg: weightKg, reps: 8),
                HistorySet(kind: .working, weightKg: weightKg, reps: 8),
                HistorySet(kind: .amrap, weightKg: weightKg, reps: amrapReps)
            ]
        )
    }

    @Test("doubling the target reps on the AMRAP set doubles the increment")
    func doublingTargetDoublesIncrement() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 16)], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 105 })
        #expect(result.reason.kind == .increase)
    }

    @Test("a first AMRAP miss repeats the weight")
    func firstMissRepeats() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 5)], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 100 })
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 1)
    }

    @Test("a second consecutive AMRAP miss backs the weight off 10%")
    func secondMissResets10Percent() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 5)],
            stall: StallState(consecutiveMisses: 1, lastWeightKg: 100)
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 90 })
        #expect(result.reason.kind == .deload)
        #expect(result.stall.consecutiveMisses == 0)
    }

    @Test("hitting between target and double target adds the normal increment")
    func normalIncrementBetweenTargets() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 10)], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 102.5 })
        #expect(result.reason.kind == .increase)
    }

    @Test("exactly hitting the target adds the normal increment")
    func exactTargetIsNormal() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 8)], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 102.5 })
    }
}
