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

    @Test("the back-off copy is derived from the miss fraction, not hard-coded")
    func backoffCopyMatchesConstant() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 5)],
            stall: StallState(consecutiveMisses: 1, lastWeightKg: 100)
        )
        let percent = Int(((1 - TrainingConstants.amrapMissFraction) * 100).rounded())
        #expect(ProgressionEngine.amrapMissPercent == percent)
        #expect(result.reason.body.contains("dropping \(percent)%"))
    }

    @Test("a second miss on the empty bar holds instead of backing off to the same weight")
    func secondMissOnEmptyBarHolds() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 5, weightKg: 20)],
            stall: StallState(consecutiveMisses: 1, lastWeightKg: 20),
            grid: .plates(bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets.allSatisfy { $0.weightKg == 20 })
    }

    @Test("a second miss on a 4 kg dumbbell backs off to 2 kg, not below")
    func secondMissFlooredAtGrid() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 5, weightKg: 4)],
            stall: StallState(consecutiveMisses: 1, lastWeightKg: 4), grid: .step(2)
        )
        #expect(result.reason.kind == .deload)
        #expect(result.sets.allSatisfy { $0.weightKg == 2 })
    }

    @Test("hitting between target and double target adds the normal increment")
    func normalIncrementBetweenTargets() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 10)], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 102.5 })
        #expect(result.reason.kind == .increase)
    }

    @Test("no rep target on the AMRAP set holds instead of increasing")
    func noTargetHolds() {
        let untargeted = [
            PlannedSetSpec(kind: .working), PlannedSetSpec(kind: .working), PlannedSetSpec(kind: .amrap)
        ]
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: untargeted, history: [entry(amrapReps: 0)], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 100 })
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 0)
    }

    @Test("exactly hitting the target adds the normal increment")
    func exactTargetIsNormal() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 8)], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 102.5 })
    }

    @Test("a big AMRAP on a coarse rack holds rather than jumping to the next rung")
    func oversizedRungHolds() {
        // 25s and 10s: above 40 kg the rack's next load is 70. A doubled increment (5 kg) is
        // still nowhere near a 30 kg rung.
        let coarse = [PlateStock(weightKg: 25, count: 4), PlateStock(weightKg: 10, count: 2)]
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(amrapReps: 16, weightKg: 40)],
            stall: StallState(), grid: .plates(bar: .olympic, plates: coarse, collarsKg: 0)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets.allSatisfy { $0.weightKg == 40 })
        #expect(result.reason.body.contains("70 kg"))
    }
}
