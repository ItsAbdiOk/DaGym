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
            rule: rule, planned: planned(3, reps: 10), history: [entry(reps: [10, 12, 11])],
            stall: StallState()
        )
        #expect(result.sets.count == 3)
        #expect(result.sets.allSatisfy { $0.reps == 11 })
        #expect(result.stall.lastTargetReps == 11)
        #expect(result.stall.lastPlanTargetReps == 10)
    }

    @Test("a set under the reps asked for repeats the ask instead of regressing below it")
    func missRepeatsTheAsk() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3, reps: 10), history: [entry(reps: [12, 12, 8])],
            stall: StallState(lastTargetReps: 12, lastPlanTargetReps: 10)
        )
        #expect(result.sets.count == 3)
        #expect(result.sets.allSatisfy { $0.reps == 12 })
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.lastTargetReps == 12)
    }

    @Test("hitting the reps asked for on every set climbs from the ask, not the plan")
    func hitClimbsFromTheAsk() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3, reps: 10), history: [entry(reps: [12, 12, 12])],
            stall: StallState(lastTargetReps: 12, lastPlanTargetReps: 10)
        )
        #expect(result.sets.allSatisfy { $0.reps == 13 })
        #expect(result.reason.kind == .increase)
        #expect(result.stall.lastTargetReps == 13)
    }

    @Test("adding a set drops the reps back to the plan's base")
    func addedSetResetsRepsToPlanBase() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3, reps: 10), history: [entry(reps: [15, 15, 15])],
            stall: StallState(lastTargetReps: 15, lastPlanTargetReps: 10)
        )
        #expect(result.sets.count == 4)
        #expect(result.sets.allSatisfy { $0.reps == 10 })
        #expect(result.reason.kind == .increase)
        #expect(result.stall.lastTargetReps == 10)
    }

    @Test("a plan edited since the engine last asked outranks its memory")
    func planEditOutranksMemory() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3, reps: 8), history: [entry(reps: [8, 8, 8])],
            stall: StallState(lastTargetReps: 12, lastPlanTargetReps: 10)
        )
        #expect(result.sets.allSatisfy { $0.reps == 9 })
        #expect(result.reason.kind == .increase)
    }

    @Test("per-side totals step by 2 and stay even")
    func perSideStepsByTwo() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(3, reps: 10), history: [entry(reps: [14, 14, 14])],
            stall: StallState(lastTargetReps: 14, lastPlanTargetReps: 10), perSide: true
        )
        #expect(result.sets.allSatisfy { $0.reps == 16 })
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

    /// The ladder has to actually climb. The plan's set count never moves, so sizing the ask from
    /// the plan alone meant "+1 set" was re-proposed off the plan's own count every session: the
    /// prescription sat at plan + 1 for ever, `maxSets` was unreachable and the harder-variation
    /// hand-off never fired. The engine now remembers the rung it asked for.
    @Test("the set ladder climbs past plan + 1 and reaches maxSets, then hands off")
    func setLadderClimbsToMaxSets() {
        var stall = StallState()
        var counts: [Int] = []
        var lastReason = PrescriptionReason.Kind.repeat
        // The plan always says 3 sets; the lifter always hits the ceiling on every set they are
        // asked for. 3 → 4 → 5 sets, then "go harder".
        for asked in [3, 4, 5] {
            let result = ProgressionEngine.prescribe(
                rule: rule, planned: planned(3),
                history: [entry(reps: Array(repeating: 15, count: asked))], stall: stall
            )
            counts.append(result.sets.count)
            lastReason = result.reason.kind
            stall = result.stall
        }
        #expect(counts == [4, 5, 5])
        #expect(lastReason == .plan)
        #expect(stall.lastTargetSets == 5)
    }

    @Test("re-sizing the plan outranks the remembered rung")
    func planResizeOutranksMemory() {
        let stall = StallState(
            lastTargetReps: 15, lastPlanTargetReps: 15, lastTargetSets: 4, lastPlanTargetSets: 3
        )
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned(2), history: [entry(reps: [10, 10])], stall: stall
        )
        #expect(result.sets.count == 2)
    }
}
