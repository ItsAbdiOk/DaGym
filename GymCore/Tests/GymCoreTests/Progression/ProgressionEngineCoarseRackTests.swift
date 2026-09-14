import Foundation
import Testing
@testable import GymCore

/// `RuleContext.oversizedRung`: a plate rack too coarse for the rule's increment holds instead
/// of prescribing the whole rung (`TrainingConstants.maxGridStepIncrements`).
@Suite("Progression engine — coarse racks")
struct ProgressionEngineCoarseRackTests {
    private let planned = [PlannedSetSpec(kind: .working, targetReps: 8)]

    private func history(reps: Int, weightKg: Double) -> [ExerciseHistoryEntry] {
        [ExerciseHistoryEntry(
            date: .now, sets: (0..<3).map { _ in HistorySet(kind: .working, weightKg: weightKg, reps: reps) }
        )]
    }

    /// 25s and 10s only: the rung above 40 kg is 70. `maxSessionIncreaseFraction` is meant to
    /// stop exactly this, and "one grid step always wins" used to hand it back as "+30 kg".
    private static let coarseRack = [PlateStock(weightKg: 25, count: 4), PlateStock(weightKg: 10, count: 2)]

    @Test("a hit whose next rung is a 75 % jump holds, and says why")
    func oversizedRungHolds() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned, history: history(reps: 8, weightKg: 40),
            stall: StallState(),
            grid: .plates(bar: .olympic, plates: Self.coarseRack, collarsKg: 0)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets.allSatisfy { $0.weightKg == 40 })
        #expect(result.reason.title == "Repeat 40 kg")
        #expect(result.reason.body.contains("70 kg"))
        #expect(result.reason.body.contains("75 %"))
        // A hit, not a miss: the streak is clear and stays at this weight.
        #expect(result.stall.consecutiveMisses == 0)
        #expect(result.stall.lastWeightKg == 40)
    }

    @Test("a home rack of 20s and 10s at 60 kg holds rather than prescribing +20")
    func homeRackHolds() {
        let rack = [PlateStock(weightKg: 20, count: 4), PlateStock(weightKg: 10, count: 4)]
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned, history: history(reps: 8, weightKg: 60),
            stall: StallState(), grid: .plates(bar: .olympic, plates: rack, collarsKg: 0)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets.allSatisfy { $0.weightKg == 60 })
    }

    @Test("an ordinary grid step past the fraction cap is still taken: 12 → 14 kg dumbbells")
    func smallStepPastCapStillIncreases() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned, history: history(reps: 8, weightKg: 12),
            stall: StallState(), grid: .step(2)
        )
        #expect(result.reason.kind == .increase)
        #expect(result.sets.allSatisfy { $0.weightKg == 14 })
    }

    @Test("an empty bar with only 2.5 kg plates goes to 25: two increments is within the line")
    func emptyBarWithSmallPlatesIncreases() {
        let result = ProgressionEngine.prescribe(
            rule: .linear(incrementKg: 2.5), planned: planned, history: history(reps: 8, weightKg: 20),
            stall: StallState(),
            grid: .plates(bar: .olympic, plates: [PlateStock(weightKg: 2.5, count: 2)], collarsKg: 0)
        )
        #expect(result.reason.kind == .increase)
        #expect(result.sets.allSatisfy { $0.weightKg == 25 })
    }
}
