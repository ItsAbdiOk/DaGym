import Foundation
import GymCore
import SwiftData
import Testing
@testable import DaGym

/// The launch-time pieces `RootView` runs after the store is ready: the Resume/Discard prompt
/// for a workout a crash left unfinished, and the Siri / Control Center hand-off that must
/// wait for today's routine before it is consumed.
@Suite("RootView launch: resume prompt and intent hand-off", .serialized)
@MainActor
struct ResumeSheetTests {
    private func makeRoutine(_ store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 80)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", rule: nil, exercises: [draft]).id
    }

    private func makeBench(_ store: WorkoutStore) -> ExerciseInfo {
        store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
    }

    @Test("an unfinished workout at launch becomes the resume prompt; a finished one does not")
    func unfinishedWorkoutPromptsResume() throws {
        let store = try makeStore()
        let routineID = makeRoutine(store, exerciseID: makeBench(store).id)
        #expect(UnfinishedWorkoutPrompt.newest(in: store) == nil)

        let finished = store.startWorkout(routineID: routineID)
        finished.exercises[0].sets[0].isDone = true
        _ = store.finish(session: finished)
        #expect(UnfinishedWorkoutPrompt.newest(in: store) == nil)

        let live = store.startWorkout(routineID: routineID)
        live.exercises[0].sets[0].isDone = true
        store.sync(session: live)
        let liveID = try #require(live.workoutID)

        let prompt = try #require(UnfinishedWorkoutPrompt.newest(in: store))
        #expect(prompt.id == liveID)
        #expect(prompt.title == live.title)
        #expect(prompt.setsDone == 1)
        #expect(prompt.detail.hasSuffix("1 set logged"))

        // Resume hydrates the same workout; Discard deletes it, and the prompt goes with it.
        let resumed = try #require(store.resumeSession(for: prompt.id))
        #expect(resumed.workoutID == liveID)
        store.deleteWorkout(id: prompt.id)
        #expect(UnfinishedWorkoutPrompt.newest(in: store) == nil)
        #expect(store.history().count == 1)
    }

    @Test("an in-progress workout does not count as a session on the exercise")
    func sessionCountIgnoresUnfinished() throws {
        let store = try makeStore()
        let bench = makeBench(store)
        let routineID = makeRoutine(store, exerciseID: bench.id)
        let model = try #require(store.fetchExerciseModel(id: bench.id))

        let finished = store.startWorkout(routineID: routineID)
        finished.exercises[0].sets[0].isDone = true
        _ = store.finish(session: finished)
        #expect(store.exerciseInfo(for: model).sessions == 1)

        let live = store.startWorkout(routineID: routineID)
        store.sync(session: live)
        #expect(store.unfinishedWorkouts().count == 1)
        #expect(store.exerciseInfo(for: model).sessions == 1)
    }

    @Test("a start-workout flag set before the routine loads is kept, then consumed exactly once")
    func intentFlagWaitsForRoutine() {
        _ = PendingIntentHandoff.consume(routineLoaded: true)
        PendingWorkoutIntentAction.requestStartWorkout()

        #expect(PendingIntentHandoff.consume(routineLoaded: false).isEmpty)
        #expect(PendingIntentHandoff.consume(routineLoaded: true) == [.startWorkout])
        #expect(PendingIntentHandoff.consume(routineLoaded: true).isEmpty)
    }

    @Test("rest-timer and start-workout flags are both delivered, rest timer first")
    func bothFlagsDelivered() {
        _ = PendingIntentHandoff.consume(routineLoaded: true)
        PendingWorkoutIntentAction.requestStartWorkout()
        PendingIntentAction.requestStartRestTimer()

        #expect(PendingIntentHandoff.consume(routineLoaded: true) == [.startRestTimer, .startWorkout])
        #expect(PendingIntentHandoff.consume(routineLoaded: true).isEmpty)
    }
}
