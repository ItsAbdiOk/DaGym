import Foundation
import Testing
@testable import GymCore

@Suite("Progression engine — percent / training max")
struct ProgressionEngineTrainingMaxTests {
    private let rule = ProgressionRule.percentOfTrainingMax(scheme: .classic)

    private func prescribe(weekInCycle: Int, trainingMaxKg: Double?) -> Prescribed {
        ProgressionEngine.prescribe(
            rule: rule, planned: [], history: [], stall: StallState(),
            trainingMaxKg: trainingMaxKg, weekInCycle: weekInCycle
        )
    }

    @Test("weeks 2 through 4 of a 100 kg TM match the plan.md §7 wave")
    func waveNumbersFor100kgTM() {
        let week2 = prescribe(weekInCycle: 2, trainingMaxKg: 100)
        #expect(week2.sets.map(\.weightKg) == [70, 80, 90])
        #expect(week2.sets.map(\.reps) == [3, 3, 3])
        #expect(week2.trainingMaxKg == 100)

        let week3 = prescribe(weekInCycle: 3, trainingMaxKg: 100)
        #expect(week3.sets.map(\.weightKg) == [75, 85, 95])
        #expect(week3.sets.map(\.reps) == [5, 3, 1])

        let week4 = prescribe(weekInCycle: 4, trainingMaxKg: 100)
        #expect(week4.sets.map(\.weightKg) == [40, 50, 60])
        #expect(week4.sets.map(\.reps) == [5, 5, 5])
    }

    @Test("a light week on a barbell never lands below the empty bar")
    func lightWeekFloorsAtTheBar() {
        let week4 = ProgressionEngine.prescribe(
            rule: rule, planned: [], history: [], stall: StallState(), trainingMaxKg: 40, weekInCycle: 4,
            grid: .plates(bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
        )
        #expect(week4.sets.map(\.weightKg) == [20, 20, 25])
    }

    @Test("a new cycle bumps the TM before computing the wave")
    func newCycleBumpsTrainingMax() {
        // Cycle 2's week 1 is computed off the bumped TM: 100 + 2.5 = 102.5.
        let week1 = ProgressionEngine.prescribe(
            rule: rule, planned: [], history: [], stall: StallState(trainingMaxCycle: 1),
            trainingMaxKg: 100, weekInCycle: 1, cycleIndex: 2
        )
        #expect(week1.trainingMaxKg == 102.5)
        #expect(week1.stall.trainingMaxCycle == 2)
        let expected = [0.65, 0.75, 0.85].map {
            LoadGrid.plates(bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
                .nearest(102.5 * $0)
        }
        #expect(week1.sets.map(\.weightKg) == expected)
    }

    @Test("the same cycle never bumps the training max, whatever the week")
    func sameCycleDoesNotBump() {
        let week3 = prescribe(weekInCycle: 3, trainingMaxKg: 100)
        #expect(week3.trainingMaxKg == 100)
        let week1 = ProgressionEngine.prescribe(
            rule: rule, planned: [], history: [], stall: StallState(trainingMaxCycle: 2),
            trainingMaxKg: 100, weekInCycle: 1, cycleIndex: 2
        )
        #expect(week1.trainingMaxKg == 100)
    }

    @Test("a week outside the wave is a plan problem, not 'no history'")
    func weekOutsideWave() {
        let result = prescribe(weekInCycle: 5, trainingMaxKg: 100)
        #expect(result.reason.kind == .repeat)
        #expect(result.reason.title == "Week 5")
    }

    @Test("no TM and no history prescribes a first-time entry")
    func firstTime() {
        let result = prescribe(weekInCycle: 1, trainingMaxKg: nil)
        #expect(result.reason.kind == .firstTime)
    }

    @Test("no TM but existing history computes TM as 90% of e1RM")
    func computesTMFromHistoryWhenUnset() {
        let entry = ExerciseHistoryEntry(
            date: .now, sets: [HistorySet(kind: .working, weightKg: 100, reps: 1)]
        )
        let result = ProgressionEngine.prescribe(
            rule: rule, planned: [], history: [entry], stall: StallState(),
            trainingMaxKg: nil, weekInCycle: 2
        )
        // e1RM of a single rep at 100 kg is 100 kg -> TM = 90.
        #expect(result.trainingMaxKg == 90)
    }
}
