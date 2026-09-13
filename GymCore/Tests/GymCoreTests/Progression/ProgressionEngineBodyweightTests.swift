import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — bodyweight")
struct ProgressionEngineBodyweightTests {
    private let rule = ProgressionRule.bodyweight(repCeiling: 15, maxSets: 5)

    private func entry(reps: [Int]) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(date: .now, sets: reps.map { HistorySet(kind: .working, weightKg: 0, reps: $0) })
    }

    private func planned(_ sets: Int, reps: Int = 15) -> [PlannedSetSpec] {
        (0..<sets).map { _ in PlannedSetSpec(kind: .working, targetReps: reps) }
    }

    @Test("hitting the rep ceiling with room to grow adds a set")
    func addsASetAtCeiling() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3), history: [entry(reps: [15, 15, 15])], stall: StallState()
        )
        #expect(result.sets.count == 4)
        #expect(result.sets.allSatisfy { $0.reps == 15 })
        #expect(result.reason.kind == .increase)
    }

    @Test("maxing out sets at the ceiling suggests a harder variation instead of more volume")
    func suggestsHarderVariationAtMax() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(5), history: [entry(reps: [15, 15, 15, 15, 15])], stall: StallState()
        )
        #expect(result.sets.count == 5)
        #expect(result.reason.kind == .plan)
    }

    @Test("below the ceiling asks for one more rep on the weakest set")
    func climbsTowardCeiling() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3), history: [entry(reps: [10, 12, 11])], stall: StallState()
        )
        #expect(result.sets.count == 3)
        #expect(result.sets.allSatisfy { $0.reps == 11 })
    }

    @Test("a partial session holds the plan instead of shrinking it")
    func partialSessionHolds() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3), history: [entry(reps: [15])], stall: StallState()
        )
        #expect(result.sets.count == 3)
        #expect(result.sets.allSatisfy { $0.reps == 15 })
        #expect(result.reason.kind == .repeat)
    }

    @Test("extra sets beyond the plan don't count as maxing out")
    func extraSetsDoNotMaxOut() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3), history: [entry(reps: [15, 15, 15, 15, 15])], stall: StallState()
        )
        #expect(result.sets.count == 4)
        #expect(result.reason.kind == .increase)
    }

    @Test("no history prescribes a first-time entry")
    func firstTime() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3), history: [], stall: StallState()
        )
        #expect(result.reason.kind == .firstTime)
    }
}
