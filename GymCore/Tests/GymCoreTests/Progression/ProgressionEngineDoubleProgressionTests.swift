import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — double progression")
struct ProgressionEngineDoubleProgressionTests {
    private let rule = ProgressionRule.doubleProgression(low: 8, high: 12, incrementKg: 2.5)
    private let planned = (0..<3).map { _ in PlannedSetSpec(kind: .working, targetReps: 12) }

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

    @Test("one set of 12 out of three planned is a hold, not the top of the range")
    func partialSessionHolds() {
        let history = [entry(reps: [12], weightKg: 50)]
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: history, stall: StallState()
        )
        #expect(result.sets.count == 3)
        #expect(result.sets.allSatisfy { $0.weightKg == 50 })
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 0)
    }

    /// The first session at a weight sets the bar rather than missing it: it has nothing to beat.
    /// So `doubleProgressionMissesBeforeDeload` (3) real chances to add a rep means four sessions
    /// at the weight, and the deload's own copy — "3 sessions … without adding a rep" — is now
    /// literally true. Counting the first session made it three sessions and two real chances.
    @Test("the first session sets the bar; three later sessions without a rep then deload")
    func stallAgainstBestOfRun() {
        var stall = StallState()
        var last: Prescribed?
        for reps in [[10, 10, 10], [10, 9, 10], [10, 10, 10], [10, 9, 9]] {
            last = ProgressionEngine.prescribe(
                rule: rule, planned: planned, history: [entry(reps: reps, weightKg: 40)], stall: stall,
                grid: .step(2.5)
            )
            stall = last?.stall ?? stall
        }
        #expect(last?.reason.kind == .deload)
        #expect(last?.sets[0].weightKg == 37.5)
        #expect(last?.stall.consecutiveMisses == 0)
    }

    @Test("each session that beats the run's best keeps the miss count at zero")
    func improvingEachSessionNeverStalls() {
        var stall = StallState(lastWeightKg: 40, lastWeakestReps: 8, bestWeakestReps: 8)
        for (reps, next) in [(9, 10), (10, 11), (11, 12)] {
            let result = ProgressionEngine.prescribe(
                rule: rule, planned: planned, history: [entry(reps: [reps, reps, reps], weightKg: 40)],
                stall: stall, grid: .step(2.5)
            )
            #expect(result.stall.consecutiveMisses == 0)
            #expect(result.stall.bestWeakestReps == reps)
            #expect(result.sets[0].reps == next)
            stall = result.stall
        }
    }

    @Test("a weight change resets the run's best, and the first session at the new weight is no miss")
    func weightChangeResetsBest() {
        let stall = StallState(
            consecutiveMisses: 1, lastWeightKg: 40, lastWeakestReps: 10, bestWeakestReps: 10
        )
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(reps: [8, 7, 6], weightKg: 42.5)], stall: stall,
            grid: .step(2.5)
        )
        // 6 reps at 42.5 kg is not a "miss": there is no earlier session at 42.5 kg to have
        // beaten. It records the bar (6) the next session has to clear.
        #expect(result.stall.consecutiveMisses == 0)
        #expect(result.stall.bestWeakestReps == 6)
        #expect(result.stall.lastWeightKg == 42.5)
    }

    @Test("per-side totals step by 2")
    func perSideStepsByTwo() {
        let result = ProgressionEngine.prescribe(
            rule: .doubleProgression(low: 12, high: 20, incrementKg: 2.5),
            planned: planned, history: [entry(reps: [16, 16, 16], weightKg: 10)], stall: StallState(),
            grid: .step(2), perSide: true
        )
        #expect(result.sets.allSatisfy { $0.reps == 18 })
    }

    @Test("a per-side odd range is rounded up to even, and its rounded top adds weight")
    func perSideOddRangeRoundsUp() {
        let odd = ProgressionRule.doubleProgression(low: 7, high: 13, incrementKg: 2.5)
        let atThirteen = ProgressionEngine.prescribe(
            rule: odd, planned: planned, history: [entry(reps: [13, 13, 13], weightKg: 10)],
            stall: StallState(), grid: .step(2), perSide: true
        )
        #expect(atThirteen.sets.allSatisfy { $0.weightKg == 10 && $0.reps == 14 })
        let atFourteen = ProgressionEngine.prescribe(
            rule: odd, planned: planned, history: [entry(reps: [14, 14, 14], weightKg: 10)],
            stall: StallState(), grid: .step(2), perSide: true
        )
        #expect(atFourteen.reason.kind == .increase)
        #expect(atFourteen.sets.allSatisfy { $0.weightKg == 12 && $0.reps == 8 })
    }

    @Test("a stall at the lightest dumbbell holds instead of prescribing a deload to zero")
    func stallAtLightestLoadHolds() {
        let stall = StallState(consecutiveMisses: 2, lastWeightKg: 2, lastWeakestReps: 8, bestWeakestReps: 8)
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [entry(reps: [8, 8, 8], weightKg: 2)], stall: stall,
            grid: .step(2)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets.allSatisfy { $0.weightKg == 2 })
        #expect(result.reason.title.localizedCaseInsensitiveContains("lightest"))
    }

    @Test("no history prescribes a first-time entry")
    func firstTime() {
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: planned, history: [], stall: StallState()
        )
        #expect(result.reason.kind == .firstTime)
    }
}
