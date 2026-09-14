import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — assisted")
struct ProgressionEngineAssistedTests {
    private let planned = [PlannedSetSpec(kind: .working, targetReps: 8)]

    private func entry(reps: Int, assistanceKg: Double) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            date: .now,
            sets: [HistorySet(kind: .working, weightKg: 0, reps: reps, assistanceKg: assistanceKg)]
        )
    }

    @Test("hitting every rep target reduces assistance by one step")
    func hitReducesAssistance() {
        let result = ProgressionEngine.prescribe(
            rule: .assisted(stepKg: 2.5), planned: planned, history: [entry(reps: 8, assistanceKg: 20)],
            stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 17.5 && $0.assistanceKg == 17.5 })
        #expect(result.reason.kind == .increase)
        #expect(result.reason.title == "−2.5 kg assist")
    }

    /// `Prescription` writes the assistance into both `weightKg` and `assistanceKg`; the log
    /// screen's weight field only writes `weightKg`. So when the two disagree, the weight is what
    /// the lifter actually typed and `assistanceKg` is the stale prescription — reading the stale
    /// one stepped down from a number the lifter never used.
    @Test("a retyped weight wins over a stale assistanceKg")
    func retypedWeightWinsOverStaleAssistance() {
        let logged = ExerciseHistoryEntry(
            date: .now,
            sets: [HistorySet(kind: .working, weightKg: 30, reps: 8, assistanceKg: 20)]
        )
        let result = ProgressionEngine.prescribe(
            rule: .assisted(stepKg: 2.5), planned: planned, history: [logged], stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.assistanceKg == 27.5 })
    }

    @Test("assistance never drops below the floor")
    func clampsToFloor() {
        let result = ProgressionEngine.prescribe(
            rule: .assisted(stepKg: 2.5), planned: planned, history: [entry(reps: 8, assistanceKg: 1)],
            stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 0 })
    }

    @Test("missing the rep target repeats the same assistance")
    func missRepeats() {
        let result = ProgressionEngine.prescribe(
            rule: .assisted(stepKg: 2.5), planned: planned, history: [entry(reps: 5, assistanceKg: 20)],
            stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 20 })
        #expect(result.reason.kind == .repeat)
    }
}

@Suite("Progression engine — timed")
struct ProgressionEngineTimedTests {
    private let planned = [PlannedSetSpec(kind: .working, targetSeconds: 30)]

    private func entry(durationSeconds: Int) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            date: .now,
            sets: [HistorySet(kind: .working, weightKg: 0, reps: 1, durationSeconds: durationSeconds)]
        )
    }

    @Test("hitting the hold adds seconds")
    func hitAddsSeconds() {
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: planned, history: [entry(durationSeconds: 30)],
            stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.durationSeconds == 35 })
        #expect(result.reason.kind == .increase)
    }

    @Test("missing the hold repeats the hold that was asked for, not the shorter one held")
    func missRepeatsAskedDuration() {
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: planned, history: [entry(durationSeconds: 20)],
            stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.durationSeconds == 30 })
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.lastTargetSeconds == 30)
    }

    @Test("three short holds in a row back the ask off to 90 %, rounded down to 5 s")
    func thirdMissBacksOff() {
        var stall = StallState(lastTargetSeconds: 60, lastPlanTargetSeconds: 30)
        var last: Prescribed?
        for _ in 0..<3 {
            last = ProgressionEngine.prescribe(
                rule: .timed(stepSeconds: 5), planned: planned, history: [entry(durationSeconds: 45)],
                stall: stall
            )
            stall = last?.stall ?? stall
        }
        #expect(last?.reason.kind == .deload)
        #expect(last?.sets.allSatisfy { $0.durationSeconds == 50 } == true)
        #expect(last?.stall.consecutiveMisses == 0)
        #expect(last?.stall.lastTargetSeconds == 50)
    }

    @Test("a back-off never goes under one step")
    func backoffFlooredAtOneStep() {
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: planned, history: [entry(durationSeconds: 4)],
            stall: StallState(consecutiveMisses: 2, lastTargetSeconds: 10, lastPlanTargetSeconds: 30)
        )
        #expect(result.reason.kind == .deload)
        #expect(result.sets.allSatisfy { $0.durationSeconds == 5 })
    }

    @Test("a hold already at one step repeats instead of backing off")
    func backoffAtOneStepRepeats() {
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: planned, history: [entry(durationSeconds: 3)],
            stall: StallState(consecutiveMisses: 2, lastTargetSeconds: 5, lastPlanTargetSeconds: 30)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets.allSatisfy { $0.durationSeconds == 5 })
    }

    @Test("the engine's remembered hold outranks an unchanged plan target")
    func rememberedHoldOutranksStalePlan() {
        let stall = StallState(lastTargetSeconds: 60, lastPlanTargetSeconds: 30)
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: planned, history: [entry(durationSeconds: 60)],
            stall: stall
        )
        #expect(result.sets.allSatisfy { $0.durationSeconds == 65 })
    }

    @Test("a plan edited since the engine last set a hold outranks its memory")
    func editedPlanOutranksMemory() {
        let edited = [PlannedSetSpec(kind: .working, targetSeconds: 90)]
        let stall = StallState(lastTargetSeconds: 60, lastPlanTargetSeconds: 30)
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: edited, history: [entry(durationSeconds: 60)], stall: stall
        )
        #expect(result.sets.allSatisfy { $0.durationSeconds == 90 })
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.lastPlanTargetSeconds == 90)
    }

    @Test("a weighted hold keeps its load on the prescription")
    func weightedHoldKeepsLoad() {
        let history = [ExerciseHistoryEntry(date: .now, sets: [
            HistorySet(kind: .working, weightKg: 10, reps: 1, durationSeconds: 30)
        ])]
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: planned, history: history, stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 10 && $0.durationSeconds == 35 })
    }

    @Test("no history prescribes a first-time entry")
    func firstTime() {
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: planned, history: [], stall: StallState()
        )
        #expect(result.reason.kind == .firstTime)
    }
}
