// Scenario / regression pins from the engine review (docs/engine-review.md).
// Each test started life as a `withKnownIssue` probe reproducing one numbered
// finding; the wrapper came off as the fix landed. Multi-session runs are the
// template for any future rule change — a rule that looks fine on one session
// can still drift, creep or loop over ten.
import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — review scenarios")
struct ProgressionScenarioTests {
    private func entry(_ reps: [Int], at weight: Double, rpe: [Double?]? = nil, kinds: [SetKind]? = nil,
                       daysAgo: Int = 0) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            date: Date.now.addingTimeInterval(Double(-daysAgo) * 86_400),
            sets: reps.indices.map { index in
                HistorySet(kind: kinds?[index] ?? .working, weightKg: weight, reps: reps[index],
                           effort: rpe?[index].map { Effort(rpe: $0) })
            }
        )
    }

    private let threeByFive = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 5) }

    // MARK: F1 — linear deload

    @Test("F1: linear deload after 3 misses actually reduces the weight (100 → 90)")
    func linearDeloadReducesWeight() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: threeByFive,
            history: [entry([5, 5, 3], at: 100)],
            stall: StallState(consecutiveMisses: 2, lastWeightKg: 100)
        )
        #expect(result.reason.kind == .deload)
        #expect(result.sets.allSatisfy { $0.weightKg == 90 })
        #expect(result.reason.title == "Deload to 90 kg")
    }

    @Test("F1: 10-session linear run with realistic misses deloads on the 3rd miss, twice")
    func linearTenSessions() {
        var stall = StallState()
        var weight = 100.0
        var sequence: [Double] = []
        // hit, hit, miss, miss, miss (→ deload), hit, miss, miss, miss (→ deload), hit
        let logged: [[Int]] = [[5, 5, 5], [5, 5, 5], [5, 5, 4], [5, 4, 4], [5, 4, 3],
                               [5, 5, 5], [5, 5, 4], [5, 4, 4], [5, 4, 3], [5, 5, 5]]
        for reps in logged {
            let r = ProgressionEngine.prescribe(
                rule: .linear(incrementKg: 2.5), planned: threeByFive,
                history: [entry(reps, at: weight)], stall: stall
            )
            stall = r.stall
            weight = r.sets[0].weightKg
            sequence.append(weight)
        }
        #expect(sequence == [102.5, 105, 105, 105, 92.5, 95, 95, 95, 85, 87.5])
        #expect(sequence[4] < sequence[3])
        #expect(sequence[8] < sequence[7])
        // No non-deload session jumps more than 10 %.
        for (previous, next) in zip([100] + sequence, sequence) where next > previous {
            #expect(next / previous <= 1.10)
        }
    }

    // MARK: F2 — partial sessions / no targets

    @Test("F2: fewer sets than planned is a miss, not an increase")
    func partialSetsAreAMiss() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: threeByFive,
            history: [entry([5, 5], at: 100)], stall: StallState()
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 1)
        #expect(result.sets.allSatisfy { $0.weightKg == 100 })
    }

    @Test("F2b: no planned rep target holds the weight without touching the miss streak")
    func noTargetsNoIncrease() {
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working) }
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned,
            history: [entry([0, 0, 0], at: 100)], stall: StallState()
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 0)
        #expect(result.sets.allSatisfy { $0.weightKg == 100 })
    }

    @Test("F2c: assisted rule treats a partial session as a miss")
    func assistedPartialIsAMiss() {
        let history = [ExerciseHistoryEntry(date: .now, sets: [
            HistorySet(kind: .working, weightKg: 0, reps: 8, assistanceKg: 20)
        ])]
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 8) }
        let result = ProgressionEngine.prescribe(
            rule: .assisted(stepKg: 2.5), planned: planned, history: history, stall: StallState()
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets.allSatisfy { $0.assistanceKg == 20 })
    }

    // MARK: F3 — load grid

    @Test("F3: a 12 kg dumbbell hitting target goes to 14 kg on a 2 kg step grid, not the bar")
    func dumbbellRoundsToStepGrid() {
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 10) }
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2), planned: planned,
            history: [entry([10, 10, 10], at: 12)], stall: StallState(), grid: .step(2)
        )
        #expect(result.sets[0].weightKg == 14)
        #expect(result.reason.title == "+2 kg")
    }

    @Test("F3: a 5 kg machine stack at 47 kg + 2.5 goes to 50")
    func machineRoundsToStackStep() {
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 10) }
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned,
            history: [entry([10, 10, 10], at: 47)], stall: StallState(), grid: .step(5)
        )
        #expect(result.sets[0].weightKg == 50)
    }

    @Test("F3: with unknown equipment, a load lighter than the bar is never snapped up to the bar")
    func underBarDefaultNeverSnapsToBar() {
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 10) }
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2), planned: planned,
            history: [entry([10, 10, 10], at: 12)], stall: StallState()
        )
        #expect(result.sets[0].weightKg > 12)
        #expect(result.sets[0].weightKg < 20)
    }

    @Test("F3: free grid leaves the number alone; step grid rounds nearest/below/above")
    func gridMath() {
        #expect(LoadGrid.free.nearest(13.3) == 13.3)
        #expect(LoadGrid.step(2).nearest(13) == 14 || LoadGrid.step(2).nearest(13) == 12)
        #expect(LoadGrid.step(2).nearestBelow(13.9) == 12)
        #expect(LoadGrid.step(2).nearestAbove(12) == 14)
        #expect(LoadGrid.step(5).nearestAbove(47) == 50)
        let bar = LoadGrid.plates(bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
        #expect(bar.nearestAbove(80) == 82.5)
        #expect(bar.nearestAbove(81) == 82.5)
    }

    @Test("F3: a barbell grid never prescribes less than the empty bar")
    func barbellFloorsAtTheBar() {
        let bar = LoadGrid.plates(bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
        #expect(bar.nearest(16) == 20)
        #expect(bar.nearestBelow(18) == 20)
        #expect(bar.nearestAbove(12) == 20)
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 5) }
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned, history: [entry([3, 3, 3], at: 20)],
            stall: StallState(consecutiveMisses: 2, lastWeightKg: 20), grid: bar
        )
        #expect(result.sets[0].weightKg == 20)
    }

    // MARK: F4 / F5 — RPE rule

    @Test("F4: missing RPE holds the load instead of drifting it down")
    func rpeMissingEffortHolds() {
        let planned = [PlannedSetSpec(kind: .working, targetReps: 5, targetRPE: 8)]
        var weight = 100.0
        var sequence: [Double] = []
        for _ in 0..<5 {
            let r = ProgressionEngine.prescribe(
                rule: .rpeBased(targetRPE: 8), planned: planned,
                history: [entry([5], at: weight)], stall: StallState()
            )
            weight = r.sets[0].weightKg
            sequence.append(weight)
        }
        #expect(sequence == [100, 100, 100, 100, 100])
    }

    @Test("F5: a 7/8/9 ramp across straight sets does not ratchet the load down over 4 sessions")
    func rpeRampDoesNotDrift() {
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 5, targetRPE: 8) }
        var weight = 100.0
        var sequence: [Double] = []
        for _ in 0..<4 {
            let r = ProgressionEngine.prescribe(
                rule: .rpeBased(targetRPE: 8), planned: planned,
                history: [entry([5, 5, 5], at: weight, rpe: [7, 8, 9])], stall: StallState()
            )
            weight = r.sets[0].weightKg
            sequence.append(weight)
        }
        #expect(sequence.allSatisfy { $0 >= 100 })
        for (previous, next) in zip([100] + sequence, sequence) {
            #expect(abs(next / previous - 1) <= 0.10 + 0.001)
        }
    }

    @Test("F5: RPE 5 → target 10 is clamped to a 10 % session change")
    func rpeSwingClamped() {
        let planned = [PlannedSetSpec(kind: .working, targetReps: 5, targetRPE: 10)]
        let r = ProgressionEngine.prescribe(
            rule: .rpeBased(targetRPE: 10), planned: planned,
            history: [entry([5], at: 100, rpe: [5])], stall: StallState()
        )
        #expect(r.sets[0].weightKg <= 110)
        #expect(r.sets[0].weightKg > 100)
    }

    // MARK: F8 — lb formatting

    @Test("F8: reason titles for lb users are in lb")
    func lbReasonTitles() {
        let unit = WeightUnit.lb
        let weight = unit.toKg(135)
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 5) }
        let miss = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: unit.defaultIncrementKg), planned: planned,
            history: [entry([5, 5, 3], at: weight)], stall: StallState(),
            unit: unit, bar: unit.defaultBar, plates: WeightUnit.plateStock(for: unit)
        )
        #expect(miss.reason.title == "Repeat 135 lb")
        let hit = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: unit.defaultIncrementKg), planned: planned,
            history: [entry([5, 5, 5], at: weight)], stall: StallState(),
            unit: unit, bar: unit.defaultBar, plates: WeightUnit.plateStock(for: unit)
        )
        #expect(hit.reason.title == "+5 lb")
        #expect(unit.format(kg: hit.sets[0].weightKg) == "140")
    }

    @Test("stall streak survives a display-unit round trip of the same weight")
    func lbRoundTripKeepsStall() {
        let unit = WeightUnit.lb
        let stored = unit.toKg(135)
        let reentered = unit.toKg(unit.display(kg: stored))
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: threeByFive,
            history: [entry([5, 5, 3], at: reentered)],
            stall: StallState(consecutiveMisses: 2, lastWeightKg: stored)
        )
        #expect(result.reason.kind == .deload)
    }

    // MARK: F12 — RPE over target is a hold

    @Test("F12: RPE over target with all reps hit holds without advancing the miss streak")
    func rpeOverTargetIsAHold() {
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 5, targetRPE: 7) }
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned,
            history: [entry([5, 5, 5], at: 100, rpe: [9, 9, 9])],
            stall: StallState(consecutiveMisses: 2, lastWeightKg: 100)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 2)
        #expect(result.sets.allSatisfy { $0.weightKg == 100 })
    }

    // MARK: F14 — double progression stall

    /// Four sessions, not three: the first one at a weight has no earlier session to beat, so it
    /// sets the bar instead of missing it. `doubleProgressionMissesBeforeDeload` then buys three
    /// genuine chances to add a rep, which is what the constant and the deload's copy both say.
    @Test("F14: three sessions without a rep gained at the same weight deloads one increment")
    func doubleProgressionStalls() {
        let rule = ProgressionRule.doubleProgression(low: 8, high: 12, incrementKg: 2.5)
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 12) }
        var stall = StallState()
        var last: Prescribed?
        for reps in [[8, 7, 6], [8, 7, 6], [7, 7, 6], [8, 7, 6]] {
            last = ProgressionEngine.prescribe(
                rule: rule, planned: planned, history: [entry(reps, at: 52.5)], stall: stall
            )
            stall = last?.stall ?? stall
        }
        #expect(last?.reason.kind == .deload)
        #expect(last?.sets[0].weightKg == 50)
        #expect(last?.sets[0].reps == 12)
        #expect(last?.stall.consecutiveMisses == 0)
    }

    @Test("F14: climbing within the range resets the double-progression miss count")
    func doubleProgressionImprovementResets() {
        let rule = ProgressionRule.doubleProgression(low: 8, high: 12, incrementKg: 2.5)
        let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 12) }
        let stalled = StallState(consecutiveMisses: 2, lastWeightKg: 50, lastWeakestReps: 6)
        // Weakest set went 6 → 7: progress, so the count restarts.
        let r = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry([8, 8, 7], at: 50)], stall: stalled
        )
        #expect(r.reason.kind == .increase)
        #expect(r.stall.consecutiveMisses == 0)
        #expect(r.stall.lastWeakestReps == 7)
    }
}
