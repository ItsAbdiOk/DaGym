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
