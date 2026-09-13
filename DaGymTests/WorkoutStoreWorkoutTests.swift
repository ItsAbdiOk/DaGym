import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore workouts")
struct WorkoutStoreWorkoutTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    /// A routine saved with no progression rule: its sets are pre-filled by position from the
    /// last session (plan.md §6.1), never prescribed by the engine. Pass `rule:` for the other path.
    private func makeRoutine(store: WorkoutStore, exerciseID: UUID, rule: ProgressionRule? = nil) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", rule: rule, exercises: [draft]).id
    }

    @Test("startWorkout auto-fills from the previous session by set position when the routine has no rule")
    func autoFillsFromPrevious() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let first = store.startWorkout(routineID: routineID)
        first.exercises[0].sets[1].weightKg = 62.5
        first.exercises[0].sets[1].reps = 8
        first.exercises[0].sets[1].isDone = true
        _ = store.finish(session: first)

        let second = store.startWorkout(routineID: routineID)
        let workingSet = second.exercises[0].sets[1]
        #expect(workingSet.weightKg == 62.5)
        #expect(workingSet.reps == 8)
        #expect(workingSet.previousWeightKg == 62.5)
        #expect(workingSet.previousReps == 8)
        #expect(second.exercises[0].whyTitle == nil)
    }

    @Test("startWorkout lets the progression engine prescribe when the routine has a rule")
    func ruleWinsOverAutoFill() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id, rule: .linear(incrementKg: 2.5))

        let first = store.startWorkout(routineID: routineID)
        for index in 1...2 {
            first.exercises[0].sets[index].weightKg = 62.5
            first.exercises[0].sets[index].reps = 8
            first.exercises[0].sets[index].isDone = true
        }
        _ = store.finish(session: first)

        // Both planned working sets were done and hit their 8-rep target (skipping one would be
        // a miss), so linear adds the increment and keeps the plan's target reps — the previous
        // session still shows as the ghost.
        let second = store.startWorkout(routineID: routineID)
        let workingSet = second.exercises[0].sets[1]
        #expect(workingSet.weightKg == 65)
        #expect(workingSet.reps == 8)
        #expect(workingSet.previousWeightKg == 62.5)
        #expect(workingSet.previousReps == 8)
        #expect(second.exercises[0].whyTitle == "+2.5 kg")
    }

    @Test("finish excludes warm-ups from volume; a lower e1RM records no PR")
    func finishComputesVolumeAndPRs() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Overhead Press", primary: [.delts], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let first = store.startWorkout(routineID: routineID)
        first.exercises[0].sets[0].isDone = true
        first.exercises[0].sets[1].weightKg = 60
        first.exercises[0].sets[1].reps = 8
        first.exercises[0].sets[1].isDone = true
        let summary = store.finish(session: first)

        #expect(summary.volumeKg == 60 * 8)
        #expect(summary.prs.count == 1)

        let second = store.startWorkout(routineID: routineID)
        second.exercises[0].sets[1].weightKg = 50
        second.exercises[0].sets[1].reps = 5
        second.exercises[0].sets[1].isDone = true
        let secondSummary = store.finish(session: second)
        #expect(secondSummary.prs.isEmpty)
    }

    @Test("a backfilled workout dated before the latest one does not claim a PR")
    func backfillDoesNotClaimPR() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Deadlift", primary: [.hams], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let recent = store.startWorkout(routineID: routineID)
        recent.exercises[0].sets[1].weightKg = 120
        recent.exercises[0].sets[1].reps = 5
        recent.exercises[0].sets[1].isDone = true
        let recentSummary = store.finish(session: recent)
        #expect(recentSummary.prs.count == 1)

        let earlierDate = Date().addingTimeInterval(-60 * 60 * 24 * 30)
        let backfilled = store.startBackfill(date: earlierDate, durationMinutes: 45, routineID: routineID)
        backfilled.exercises[0].sets[1].weightKg = 140
        backfilled.exercises[0].sets[1].reps = 5
        backfilled.exercises[0].sets[1].isDone = true
        let backfilledSummary = store.finish(session: backfilled)
        #expect(backfilledSummary.prs.isEmpty)
    }

    @Test("history is newest first and excludes unfinished workouts")
    func historyOrdering() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Row", primary: [.lats], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let workoutOne = store.startWorkout(routineID: routineID)
        _ = store.finish(session: workoutOne)
        let workoutTwo = store.startWorkout(routineID: routineID)
        _ = store.finish(session: workoutTwo)
        _ = store.startWorkout(routineID: routineID)

        let history = store.history()
        #expect(history.count == 2)
        #expect(history[0].date >= history[1].date)
    }

    @Test("finish caches maxWeight and volume PRs; exerciseInfo still reports e1RM from the e1rm kind")
    func cachesAllPRKinds() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Incline Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[1].weightKg = 60
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let exerciseID: UUID? = exercise.id
        let maxWeightPredicate = #Predicate<PersonalRecordModel> {
            $0.exerciseID == exerciseID && $0.kind == "maxWeight"
        }
        let volumePredicate = #Predicate<PersonalRecordModel> {
            $0.exerciseID == exerciseID && $0.kind == "volume"
        }
        let maxWeight = try store.context.fetch(FetchDescriptor(predicate: maxWeightPredicate)).first
        let volume = try store.context.fetch(FetchDescriptor(predicate: volumePredicate)).first
        #expect(maxWeight?.value == 60)
        #expect(volume?.value == 480.0)

        let model = try #require(store.fetchExerciseModel(id: exercise.id))
        #expect(store.exerciseInfo(for: model).bestE1RM != nil)
    }

    @Test("sync persists exercise notes and the workout-level note")
    func syncPersistsNotes() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Lat Pulldown", primary: [.lats], equipment: "Machine", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)
        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].note = "Wide grip"
        session.notes = "Felt strong today"
        store.sync(session: session)

        let workoutID = try #require(session.workoutID)
        let detail = store.workoutDetail(id: workoutID)
        #expect(detail.notes == "Felt strong today")
        #expect(detail.exercises.first?.note == "Wide grip")
    }
}
