import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — RPE-based")
struct ProgressionEngineRPETests {
    @Test("recomputes load from the last set's implied e1RM")
    func recomputesLoad() {
        let entry = ExerciseHistoryEntry(
            date: .now,
            sets: [HistorySet(kind: .working, weightKg: 100, reps: 5, effort: Effort(rpe: 8))]
        )
        let planned = [PlannedSetSpec(kind: .working, targetReps: 5, targetRPE: 8)]
        let result = ProgressionEngine.prescribe(
            rule: .rpeBased(targetRPE: 8), planned: planned, history: [entry], stall: StallState()
        )
        // Same reps/RPE in and out -> the load should come back to ~100, rounded to the grid.
        let expected = WeightRounding.nearest(100, bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
        #expect(result.sets.allSatisfy { $0.weightKg == expected })
    }

    @Test("a harder RPE target for the same reps calls for more weight")
    func harderTargetMeansMoreWeight() {
        // Last session left 3 reps in the tank (RPE 7); asking for the same
        // reps at RPE 9 (only 1 left) means loading it heavier.
        let entry = ExerciseHistoryEntry(
            date: .now,
            sets: [HistorySet(kind: .working, weightKg: 100, reps: 5, effort: Effort(rpe: 7))]
        )
        let planned = [PlannedSetSpec(kind: .working, targetReps: 5, targetRPE: 9)]
        let result = ProgressionEngine.prescribe(
            rule: .rpeBased(targetRPE: 9), planned: planned, history: [entry], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg > 100 })
    }

    @Test("no history prescribes a first-time entry")
    func firstTime() {
        let result = ProgressionEngine.prescribe(
            rule: .rpeBased(targetRPE: 8), planned: [PlannedSetSpec(kind: .working, targetReps: 5)],
            history: [], stall: StallState()
        )
        #expect(result.reason.kind == .firstTime)
    }
}
