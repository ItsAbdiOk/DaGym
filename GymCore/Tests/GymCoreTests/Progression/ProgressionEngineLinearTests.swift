import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — linear")
struct ProgressionEngineLinearTests {
    private let planned = [PlannedSetSpec(kind: .working, targetReps: 8)]

    private func history(
        reps: Int, weightKg: Double, deload: Bool = false, date: Date = .now
    ) -> [ExerciseHistoryEntry] {
        [
            ExerciseHistoryEntry(
                date: date,
                sets: (0..<3).map { _ in HistorySet(kind: .working, weightKg: weightKg, reps: reps) },
                wasPlannedDeload: deload
            )
        ]
    }

    @Test("no history yet prescribes a first-time entry")
    func firstTime() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned, history: [], stall: StallState()
        )
        #expect(result.reason.kind == .firstTime)
        #expect(result.sets.count == 1)
    }

    @Test("hitting every set adds the increment")
    func happyPath() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: [PlannedSetSpec(kind: .working, targetReps: 8)],
            history: history(reps: 8, weightKg: 80), stall: StallState()
        )
        #expect(result.reason.kind == .increase)
        #expect(result.sets.allSatisfy { $0.weightKg == 82.5 })
        #expect(result.stall.consecutiveMisses == 0)
        #expect(result.stall.lastWeightKg == 82.5)
    }

    @Test("missing the rep target repeats the weight and starts a miss streak")
    func missPath() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned,
            history: history(reps: 6, weightKg: 80), stall: StallState()
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets.allSatisfy { $0.weightKg == 80 })
        #expect(result.stall.consecutiveMisses == 1)
    }

    @Test("a third consecutive miss at the same weight triggers a deload")
    func stallTriggersDeload() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned,
            history: history(reps: 6, weightKg: 80),
            stall: StallState(consecutiveMisses: 2, lastWeightKg: 80)
        )
        #expect(result.reason.kind == .deload)
        #expect(result.stall.consecutiveMisses == 0)
        // 90 % of 80 = 72, rounded down onto the 2.5 kg grid → 70 (e1RM cap 85 doesn't bind).
        #expect(result.sets.allSatisfy { $0.weightKg == 70 })
        #expect(result.stall.lastWeightKg == 70)
    }

    @Test("a deload is capped by 90% of e1RM when that's lower than 90% of the weight")
    func deloadCappedByE1RM() {
        // Three singles at 80 kg: e1RM 80 → 90 % = 72 → 70 on the grid; the same as by weight here,
        // but a weight-only deload at 80 with a 1-rep e1RM must never land above it.
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: [PlannedSetSpec(kind: .working, targetReps: 8)],
            history: history(reps: 1, weightKg: 80),
            stall: StallState(consecutiveMisses: 2, lastWeightKg: 80)
        )
        #expect(result.stall.lastWeightKg == 70)
    }

    @Test("a weight change resets the miss streak before this session is scored")
    func resetOnWeightChange() {
        // Two prior misses were recorded at 70 kg, but the baseline weight is now
        // 80 kg (changed outside the engine) — the streak should restart at 0,
        // so a miss here lands at 1 rather than tripping the 3-miss deload.
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned,
            history: history(reps: 6, weightKg: 80),
            stall: StallState(consecutiveMisses: 2, lastWeightKg: 70)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 1)
    }

    @Test("a planned deload is excluded from the baseline")
    func plannedDeloadExcluded() {
        let now = Date.now
        let history = [
            ExerciseHistoryEntry(
                date: now,
                sets: (0..<3).map { _ in HistorySet(kind: .working, weightKg: 60, reps: 5) },
                wasPlannedDeload: true
            ),
            ExerciseHistoryEntry(
                date: now.addingTimeInterval(-7 * 86_400),
                sets: (0..<3).map { _ in HistorySet(kind: .working, weightKg: 80, reps: 8) },
                wasPlannedDeload: false
            )
        ]
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned, history: history, stall: StallState()
        )
        #expect(result.reason.kind == .increase)
        #expect(result.sets.allSatisfy { $0.weightKg == 82.5 })
    }

    @Test("an increment below the plate grid still moves one grid step up")
    func roundsToPlateGrid() {
        // 80 + 1 = 81 isn't loadable; an "increase" that lands back on 80 is a lie, so take 82.5.
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 1), planned: planned,
            history: history(reps: 8, weightKg: 80), stall: StallState()
        )
        #expect(result.sets.allSatisfy { $0.weightKg == 82.5 })
        #expect(result.reason.title == "+2.5 kg")
    }

    @Test("RPE above target counts as a miss even when reps are hit")
    func rpeAboveTargetIsAMiss() {
        let entry = ExerciseHistoryEntry(
            date: .now,
            sets: (0..<3).map { _ in
                HistorySet(kind: .working, weightKg: 80, reps: 8, effort: Effort(rpe: 9))
            }
        )
        let plannedWithRPE = [PlannedSetSpec(kind: .working, targetReps: 8, targetRPE: 7)]
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: plannedWithRPE, history: [entry], stall: StallState()
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 0)
    }
}
