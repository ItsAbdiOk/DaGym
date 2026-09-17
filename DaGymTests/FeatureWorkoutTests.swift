import Foundation
import GymCore
import Testing

@testable import DaGym

/// Batch B1 of docs/reviews/opengym/features.md: superset pair/unpair, drop-set / rest-pause
/// shortcuts, the ± steppers, set undo and the plate chip's wording.
@MainActor
@Suite("Workout surface features")
struct FeatureWorkoutTests {
    private func exercise(_ name: String, rest: Int = 150, increment: Double = 2.5) -> ExerciseInfo {
        ExerciseInfo(
            name: name, primary: [.chest], equipment: "Barbell", incrementKg: increment, restSeconds: rest
        )
    }

    private func entry(
        _ name: String, weightKg: Double = 80, sets: Int = 3, group: Int? = nil, kind: SetKind = .working
    ) -> WorkoutExerciseEntry {
        let rows = (0..<sets).map { _ in SetEntry(kind: kind, weightKg: weightKg, reps: 5) }
        return WorkoutExerciseEntry(exercise: exercise(name), sets: rows, supersetGroup: group)
    }

    private func session(_ exercises: [WorkoutExerciseEntry]) -> WorkoutSession {
        let session = WorkoutSession(title: "Push", subtitle: "", startedAt: Date(), exercises: exercises)
        session.restHaptics = false
        return session
    }

    private func groups(_ session: WorkoutSession) -> [Int?] { session.exercises.map(\.supersetGroup) }

    private func single(_ name: String, rest: Int, weightKg: Double) -> WorkoutExerciseEntry {
        WorkoutExerciseEntry(
            exercise: exercise(name, rest: rest), sets: [SetEntry(weightKg: weightKg, reps: 5)]
        )
    }

    // MARK: 1 — superset pair / unpair

    @Test("pairing with the previous exercise makes a fresh two-member group")
    func pairWithPrevious() {
        let session = session([entry("Bench"), entry("Row"), entry("Curl")])
        session.pairSuperset(entryID: session.exercises[1].id, with: .previous)
        let groups = groups(session)
        #expect(groups[0] != nil)
        #expect(groups[0] == groups[1])
        #expect(groups[2] == nil)
        #expect(session.groupedIndices == [[0, 1], [2]])
    }

    @Test("pairing with the next exercise joins its existing group")
    func pairWithNextJoinsGroup() {
        let session = session([entry("Bench"), entry("Row", group: 4), entry("Curl", group: 4)])
        session.pairSuperset(entryID: session.exercises[0].id, with: .next)
        #expect(groups(session) == [4, 4, 4])
        #expect(session.groupedIndices == [[0, 1, 2]])
    }

    @Test("pairing at the edge of the list is a no-op")
    func pairAtEdge() {
        let session = session([entry("Bench"), entry("Row")])
        session.pairSuperset(entryID: session.exercises[0].id, with: .previous)
        session.pairSuperset(entryID: session.exercises[1].id, with: .next)
        #expect(groups(session) == [nil, nil])
    }

    @Test("unpairing one of two dissolves the group")
    func unpairDissolvesPair() {
        let session = session([entry("Bench", group: 1), entry("Row", group: 1), entry("Curl")])
        session.unpairSuperset(entryID: session.exercises[1].id)
        #expect(groups(session) == [nil, nil, nil])
    }

    @Test("unpairing the middle of three splits the survivors into singletons, not a broken group")
    func unpairMiddleOfThree() {
        let session = session([entry("A", group: 1), entry("B", group: 1), entry("C", group: 1)])
        session.unpairSuperset(entryID: session.exercises[1].id)
        #expect(groups(session) == [nil, nil, nil])
        #expect(session.groupedIndices == [[0], [1], [2]])
    }

    @Test("unpairing the middle of four leaves two separate pairs")
    func unpairMiddleOfFour() {
        let session = session([
            entry("A", group: 1), entry("B", group: 1), entry("C", group: 1), entry("D", group: 1)
        ])
        session.unpairSuperset(entryID: session.exercises[1].id)
        let groups = groups(session)
        #expect(groups[0] == nil)
        #expect(groups[1] == nil)
        #expect(groups[2] != nil)
        #expect(groups[2] == groups[3])
        #expect(session.groupedIndices == [[0], [1], [2, 3]])
    }

    @Test("re-pairing a grouped exercise the other way moves it instead of fusing groups")
    func repairMovesBetweenGroups() {
        let session = session([entry("A", group: 1), entry("B", group: 1), entry("C")])
        session.pairSuperset(entryID: session.exercises[1].id, with: .next)
        let groups = groups(session)
        #expect(groups[0] == nil)
        #expect(groups[1] != nil)
        #expect(groups[1] == groups[2])
    }

    @Test("a freshly paired group rests once per round on the longest member rest")
    func pairedGroupRoundRest() {
        let bench = single("Bench", rest: 150, weightKg: 80)
        let row = single("Row", rest: 90, weightKg: 60)
        let curl = single("Curl", rest: 60, weightKg: 20)
        let session = session([bench, row, curl])
        session.pairSuperset(entryID: row.id, with: .previous)
        session.completeSet(exerciseID: bench.id, setID: bench.sets[0].id)
        #expect(session.restRemaining == 0)
        #expect(session.restNextLabel == "Next Row")
        session.completeSet(exerciseID: row.id, setID: row.sets[0].id)
        #expect(session.restRemaining == 150)
    }

    // MARK: 2 — drop-set / rest-pause shortcuts

    @Test("a drop-set shortcut inserts an 80 % row directly below, snapped to the increment")
    func dropSetInsertsBelow() {
        let session = session([entry("Bench", weightKg: 100)])
        let bench = session.exercises[0]
        session.insertSet(exerciseID: bench.id, after: bench.sets[0].id, kind: .drop)
        let sets = session.exercises[0].sets
        #expect(sets.count == 4)
        #expect(sets[1].kind == .drop)
        #expect(sets[1].weightKg == 80)
        #expect(sets[1].reps == 5)
        #expect(sets[2].kind == .working)
    }

    @Test("a drop set from 22 kg at a 2 kg increment lands on 16, not 17.6")
    func dropSetSnapsDown() {
        var dumbbell = entry("Curl", weightKg: 22, sets: 1)
        dumbbell.exercise.incrementKg = 2
        let session = session([dumbbell])
        session.insertSet(exerciseID: dumbbell.id, after: dumbbell.sets[0].id, kind: .drop)
        #expect(session.exercises[0].sets[1].weightKg == 16)
    }

    @Test("a rest-pause shortcut copies the row's weight and reps")
    func restPauseInsertsCopy() {
        let session = session([entry("Bench", weightKg: 100)])
        let bench = session.exercises[0]
        session.insertSet(exerciseID: bench.id, after: bench.sets[2].id, kind: .restPause)
        let sets = session.exercises[0].sets
        #expect(sets.count == 4)
        #expect(sets[3].kind == .restPause)
        #expect(sets[3].weightKg == 100)
        #expect(sets[3].reps == 5)
    }

    @Test("completing a rest-pause set starts the short pause, not the exercise's full rest")
    func restPauseUsesShortRest() {
        let session = session([entry("Bench", weightKg: 100)])
        session.restPauseSeconds = 20
        let bench = session.exercises[0]
        session.insertSet(exerciseID: bench.id, after: bench.sets[0].id, kind: .restPause)
        let burst = session.exercises[0].sets[1]
        session.completeSet(exerciseID: bench.id, setID: burst.id)
        #expect(session.restRemaining == 20)
        #expect(session.restTotal == 20)
        session.completeSet(exerciseID: bench.id, setID: bench.sets[0].id)
        #expect(session.restRemaining == 150)
    }

    @Test("a rest-pause set that is the session's last set starts no rest at all")
    func lastRestPauseSetRestsNothing() {
        let session = session([entry("Bench", weightKg: 100, sets: 1, kind: .restPause)])
        session.restPauseSeconds = 20
        let bench = session.exercises[0]
        session.completeSet(exerciseID: bench.id, setID: bench.sets[0].id)
        #expect(session.restRemaining == 0)
        #expect(session.restNextLabel == "Last set done")
    }

    // MARK: 25 — steppers

    @Test("the steppers move weight by the delta and reps by one, never below zero")
    func adjustSetClampsAtZero() {
        let session = session([entry("Bench", weightKg: 2.5, sets: 1)])
        let bench = session.exercises[0]
        let set = bench.sets[0]
        session.adjustSet(exerciseID: bench.id, setID: set.id, weightDelta: 2.5)
        #expect(session.exercises[0].sets[0].weightKg == 5)
        session.adjustSet(exerciseID: bench.id, setID: set.id, weightDelta: -7.5)
        #expect(session.exercises[0].sets[0].weightKg == 0)
        session.adjustSet(exerciseID: bench.id, setID: set.id, repsDelta: -6)
        #expect(session.exercises[0].sets[0].reps == 0)
        session.adjustSet(exerciseID: bench.id, setID: set.id, repsDelta: 1)
        #expect(session.exercises[0].sets[0].reps == 1)
    }

    // MARK: 23 — undo

    @Test("a deleted set can be put back in its original slot with its id intact")
    func undoDeleteSetRestoresSlot() {
        let session = session([entry("Bench")])
        let bench = session.exercises[0]
        let removed = bench.sets[1]
        session.removeSet(exerciseID: bench.id, setID: removed.id)
        #expect(session.exercises[0].sets.count == 2)
        session.insertSet(removed, at: 1, exerciseID: bench.id)
        #expect(session.exercises[0].sets.map(\.id) == bench.sets.map(\.id))
    }

    @Test("putting a set back past the end appends rather than crashing")
    func undoInsertClampsIndex() {
        let session = session([entry("Bench", sets: 2)])
        let bench = session.exercises[0]
        session.insertSet(SetEntry(weightKg: 1, reps: 1), at: 9, exerciseID: bench.id)
        #expect(session.exercises[0].sets.count == 3)
        #expect(session.exercises[0].sets[2].weightKg == 1)
    }

    @Test("an undo action carries its message and runs its closure once")
    func undoActionRuns() {
        var runs = 0
        let action = UndoAction(message: "Deleted set") { runs += 1 }
        action.undo()
        #expect(action.message == "Deleted set")
        #expect(runs == 1)
    }

    // MARK: 10 — plate chip

    private func format(_ kg: Double) -> String { WorkoutSession.format(kg) }

    @Test("the plate chip reads bar plus per-side plates for a loadable weight")
    func plateChipExact() {
        let result = PlateCalculator.load(target: 100, bar: .olympic)
        #expect(PlateChip.text(for: result, format: format) == "Bar 20 · 25 + 15 per side")
    }

    @Test("the plate chip says bar only at the bar's weight")
    func plateChipBarOnly() {
        let result = PlateCalculator.load(target: 20, bar: .olympic)
        #expect(PlateChip.text(for: result, format: format) == "Bar 20 · bar only")
    }

    @Test("the plate chip flags a weight below the bar")
    func plateChipTooLight() {
        let result = PlateCalculator.load(target: 10, bar: .olympic)
        #expect(PlateChip.text(for: result, format: format) == "Bar 20 · below the bar")
    }

    @Test("the plate chip shows the nearest loadable weights either side")
    func plateChipNearest() {
        let result = PlateCalculator.load(target: 21, bar: .olympic)
        #expect(PlateChip.text(for: result, format: format) == "Bar 20 · nearest 20 / 22.5")
    }

    // MARK: keypad step

    @Test("a kg lifter keeps the exercise's own increment")
    func keypadStepKg() {
        #expect(KeypadStep.kg(2.5, unit: .kg) == 2.5)
        #expect(KeypadStep.kg(5, unit: .kg) == 5)
        #expect(KeypadStep.kg(1, unit: nil) == 1)
    }

    @Test("a lb lifter steps by whole 2.5 lb, not by 5.5 lb")
    func keypadStepLb() {
        // 2.5 kg is 5.51 lb: stepping by it walks the lifter off every round pound.
        #expect(abs(WeightUnit.lb.display(kg: KeypadStep.kg(2.5, unit: .lb)) - 5) < 0.01)
        #expect(abs(WeightUnit.lb.display(kg: KeypadStep.kg(5, unit: .lb)) - 10) < 0.01)
        // Never smaller than the lightest pair an lb rack can build.
        #expect(abs(WeightUnit.lb.display(kg: KeypadStep.kg(0.5, unit: .lb)) - 2.5) < 0.01)
    }

    @Test("the set-row ± steppers move by the same snapped step as the keypad")
    func setRowSteppersSnapForLbLifters() {
        // Raw 2.5 kg walked a lb lifter 135 → 140.5 → 146; the keypad on the same set moved by 5.
        #expect(abs(WeightUnit.lb.display(kg: SetRow.weightStepKg(2.5, unit: .lb)) - 5) < 0.01)
        #expect(SetRow.weightStepKg(2.5, unit: .kg) == 2.5)
    }

    @Test("a bodyweight keypad keeps the 0.5 lb fine step instead of snapping to plates")
    func bodyweightKeypadKeepsFineStep() {
        let fine = WeightUnit.lb.toKg(0.5)
        let unsnapped = WeightUnit.lb.display(kg: KeypadStep.kg(fine, unit: .lb, snapToPlates: false))
        #expect(abs(unsnapped - 0.5) < 0.01)
        // Logging a set still snaps.
        let snapped = WeightUnit.lb.display(kg: KeypadStep.kg(fine, unit: .lb, snapToPlates: true))
        #expect(abs(snapped - 2.5) < 0.01)
    }
}
