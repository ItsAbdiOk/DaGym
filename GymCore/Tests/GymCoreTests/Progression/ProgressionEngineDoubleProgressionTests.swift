import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — double progression")
struct ProgressionEngineDoubleProgressionTests {
    private let rule = ProgressionRule.doubleProgression(low: 8, high: 12, incrementKg: 2.5)
    private let planned = [PlannedSetSpec(kind: .working, targetReps: 12)]

    private func entry(reps: [Int], weightKg: Double) -> ExerciseHistoryEntry {
        let sets = reps.map { HistorySet(kind: .working, weightKg: weightKg, reps: $0) }
        return ExerciseHistoryEntry(date: .now, sets: sets)
    }

    @Test("reaching the top of the range adds weight and resets reps to the bottom")
    func reachingHighAddsWeight() {
        let history = [entry(reps: [12, 12, 12], weightKg: 50)]
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: history, stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 52.5 && $0.reps == 8 })
        #expect(result.reason.kind == .increase)
    }

    @Test("climbing within the range asks for one more rep, not a weight change")
    func climbingWithinRangeAsksForOneMoreRep() {
        let history = [entry(reps: [9, 8, 8], weightKg: 50)]
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: history, stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 50 && $0.reps == 9 })
    }

    @Test("the next rep target never exceeds the top of the range")
    func nextRepTargetClampsToHigh() {
        let history = [entry(reps: [12, 12, 11], weightKg: 50)]
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: history, stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.reps == 12 })
    }

    @Test("no history prescribes a first-time entry")
    func firstTime() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [], stall: StallState()
        )
        #expect(result.reason.kind == .firstTime)
    }
}
