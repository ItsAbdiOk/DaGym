import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore progression engine wiring")
struct WorkoutStoreProgressionTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(
        _ store: WorkoutStore, rule: ProgressionRule, excludeFromProgression: Bool = false
    ) -> (routineID: UUID, exerciseID: UUID) {
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)],
            excludeFromProgression: excludeFromProgression
        )
        let routine = store.saveRoutine(id: nil, name: "Push A", rule: rule, exercises: [draft])
        return (routine.id, bench.id)
    }

    /// Completes a session at `weightKg`/`reps` for its only exercise/set, then finishes it.
    private func logSession(_ store: WorkoutStore, routineID: UUID, weightKg: Double, reps: Int) {
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].weightKg = weightKg
        session.exercises[0].sets[0].reps = reps
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
    }

    @Test("hitting the target reps prescribes +2.5 kg with a matching why card")
    func linearHitPrescribesIncrement() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5))
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 8)

        let next = store.startWorkout(routineID: ids.routineID)
        let entry = try #require(next.exercises.first)
        #expect(entry.sets.first?.weightKg == 82.5)
        #expect(entry.whyTitle == "+2.5 kg")
        store.discard(session: next)
    }

    @Test("with no history a ruled exercise pre-fills the plan target, not 0 kg, with a first-time why card")
    func firstTimeUsesPlanTarget() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5))

        let session = store.startWorkout(routineID: ids.routineID)
        let entry = try #require(session.exercises.first)
        #expect(entry.sets.first?.weightKg == 80)
        #expect(entry.sets.first?.reps == 8)
        #expect(entry.sets.first?.previousWeightKg == nil)
        #expect(entry.whyKind == .firstTime)
        store.discard(session: session)
    }

    @Test("a routine saved without a rule is never prescribed by the engine")
    func ruleLessRoutineIsAutoFillOnly() throws {
        let store = try makeStore()
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)]
        )
        // The legacy "linear" label alone must not become a rule — it's display-only.
        let routine = store.saveRoutine(
            id: nil, name: "Push A", progressionRule: "linear", exercises: [draft]
        )
        logSession(store, routineID: routine.id, weightKg: 80, reps: 8)

        let next = store.startWorkout(routineID: routine.id)
        let entry = try #require(next.exercises.first)
        #expect(entry.sets.first?.weightKg == 80)
        #expect(entry.whyTitle == nil)
        store.discard(session: next)
    }

    @Test("three consecutive misses at the same weight trigger a deload")
    func threeMissesTriggerDeload() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5))

        // Three sessions in a row missing the 8-rep target at 80 kg.
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 6)
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 6)
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 6)

        let next = store.startWorkout(routineID: ids.routineID)
        let entry = try #require(next.exercises.first)
        #expect(entry.whyTitle?.contains("Deload") == true)
        // Pin the deload to GymCore's actual fraction (engine-review F1 pins this in GymCore
        // itself; this app-wiring test previously only checked `< 80`, which a broken cut to
        // 79.9 kg — or an absurd one to 20 kg — would both satisfy).
        let weight = try #require(entry.sets.first?.weightKg)
        #expect(weight <= 80 * TrainingConstants.linearDeloadFraction, "expected roughly a 10% deload")
        #expect(weight >= 40, "expected a sane deload, not a near-zero prescription")
        store.discard(session: next)
    }

    @Test("an exercise excluded from progression keeps repeating its planned weight unchanged")
    func excludedExerciseUnchanged() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5), excludeFromProgression: true)
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 8)

        let next = store.startWorkout(routineID: ids.routineID)
        let entry = try #require(next.exercises.first)
        // Excluded exercises fall back to plain auto-fill: same weight/reps as last time, no
        // engine-driven "why" card.
        #expect(entry.sets.first?.weightKg == 80)
        #expect(entry.sets.first?.reps == 8)
        #expect(entry.whyTitle == nil)
        store.discard(session: next)
    }

    @Test("the prescription reason lands on SetLogModel after sync")
    func reasonSyncsToSetLog() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5))
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 8)

        let next = store.startWorkout(routineID: ids.routineID)
        #expect(next.exercises.first?.sets.first?.prescriptionReason == "+2.5 kg")
        store.sync(session: next)

        let workoutID = try #require(next.workoutID)
        let workout = try #require(store.workout(id: workoutID))
        let setModel = try #require((workout.exercises ?? []).first?.sets?.first)
        #expect(setModel.prescriptionReason == "+2.5 kg")
        store.discard(session: next)
    }

    @Test("abandoning a workout never changes the persisted stall state")
    func abandonedWorkoutDoesNotBurnStall() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5))
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 8)

        let routineExercise = try #require(store.fetchRoutineModel(id: ids.routineID)?.exercises?.first)
        let before = routineExercise.stallStateValue

        let abandoned = store.startWorkout(routineID: ids.routineID)
        abandoned.exercises[0].sets[0].reps = 3
        abandoned.exercises[0].sets[0].isDone = true
        store.discard(session: abandoned)

        #expect(routineExercise.stallStateValue == before)
    }

    @Test("StallState's new fields round-trip through RoutineExerciseModel's JSON")
    func stallStateFieldsRoundTrip() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5))
        let routineExercise = try #require(store.fetchRoutineModel(id: ids.routineID)?.exercises?.first)

        let full = StallState(
            consecutiveMisses: 2, lastWeightKg: 80, lastWeakestReps: 6, lastTargetSeconds: 45,
            trainingMaxCycle: 3
        )
        routineExercise.stallStateValue = full
        #expect(routineExercise.stallStateValue == full)

        // Legacy two-field JSON (saved before this review) must still decode, with the new
        // fields nil.
        routineExercise.stallJSON = #"{"consecutiveMisses":1,"lastWeightKg":80}"#
        let legacy = routineExercise.stallStateValue
        #expect(legacy.consecutiveMisses == 1)
        #expect(legacy.lastWeightKg == 80)
        #expect(legacy.lastWeakestReps == nil)
        #expect(legacy.lastTargetSeconds == nil)
        #expect(legacy.trainingMaxCycle == nil)
    }

    @Test("a dumbbell exercise prescribes on the 2 kg increment grid, not the barbell grid")
    func dumbbellPrescribesOnIncrementGrid() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "DB Row", primary: [.lats], equipment: "dumbbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 10, targetWeightKg: 12)]
        )
        let routine = store.saveRoutine(
            id: nil, name: "Pull", rule: .linear(incrementKg: 2), exercises: [draft]
        )
        logSession(store, routineID: routine.id, weightKg: 12, reps: 10)

        let next = store.startWorkout(routineID: routine.id)
        let entry = try #require(next.exercises.first)
        // A barbell grid would round a +2 kg bump up to the next plate-loadable weight (20 kg);
        // the dumbbell step grid keeps it at 14.
        #expect(entry.sets.first?.weightKg == 14)
        store.discard(session: next)
    }

    @Test("the active program's cycle bumps the training max once per cycle, not every session")
    func cycleIndexBumpsTrainingMaxOncePerCycle() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .percentOfTrainingMax(scheme: .classic))
        for name in ["Pull B", "Legs"] {
            _ = store.saveRoutine(id: nil, name: name, exercises: [])
        }
        let program = try #require(store.createProgram(from: .pushPullLegs))
        store.startProgram(id: program.id)
        // `.pushPullLegs` cycles "Push A"/"Pull B"/"Legs" — this test's routine is named
        // "Push A" by `makeRoutine`, matching a starter-program slot so it picks up an active
        // cycle index; the other two slots are empty stand-ins so the program can be built.
        // The TM only initializes once there's a prior session to derive an e1RM from, so it
        // takes two finished sessions before it's first set.
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 5)
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 5)

        let routineExercise = try #require(store.fetchRoutineModel(id: ids.routineID)?.exercises?.first)
        let firstCycleTM = try #require(routineExercise.trainingMaxKg)

        // Same cycle (`cycleIndex` hasn't advanced — no time has passed): a third session must
        // not bump it again (the F6 bug this pins).
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 5)
        #expect(routineExercise.trainingMaxKg == firstCycleTM)
    }

    @Test("editing a routine's plan target after the last session wins over the ghost")
    func updatedPlanTargetWinsOverStalePrevious() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5), excludeFromProgression: true)
        logSession(store, routineID: ids.routineID, weightKg: 80, reps: 8)

        let draft = RoutineExerciseDraft(
            exerciseID: ids.exerciseID,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 90)],
            excludeFromProgression: true
        )
        store.saveRoutine(id: ids.routineID, name: "Push A", exercises: [draft])

        let next = store.startWorkout(routineID: ids.routineID)
        let entry = try #require(next.exercises.first)
        #expect(entry.sets.first?.weightKg == 90)
        store.discard(session: next)
    }

    @Test("an uncompleted set from the last session is never used as a ghost/previous")
    func uncompletedSetIsNotAPrevious() throws {
        let store = try makeStore()
        let ids = makeRoutine(store, rule: .linear(incrementKg: 2.5), excludeFromProgression: true)

        let session = store.startWorkout(routineID: ids.routineID)
        session.exercises[0].sets[0].weightKg = 80
        session.exercises[0].sets[0].reps = 8
        session.exercises[0].sets[0].isDone = false
        _ = store.finish(session: session)

        let next = store.startWorkout(routineID: ids.routineID)
        let entry = try #require(next.exercises.first)
        #expect(entry.sets.first?.previousWeightKg == nil)
        store.discard(session: next)
    }

    @Test("saving a rule with a non-positive increment rejects it, clamping to a positive step")
    func ruleEditorRejectsNonPositiveIncrement() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)]
        )
        let routine = store.saveRoutine(
            id: nil, name: "Push A", rule: .linear(incrementKg: 0), exercises: [draft]
        )
        let saved = store.fetchRoutineModel(id: routine.id)?.progressionRuleValue
        guard case .linear(let incrementKg) = saved else {
            Issue.record("expected a linear rule")
            return
        }
        #expect(incrementKg > 0)
    }
}
