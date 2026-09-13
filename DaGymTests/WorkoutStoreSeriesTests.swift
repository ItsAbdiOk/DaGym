import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore series")
struct WorkoutStoreSeriesTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    @Test("two finished workouts produce two e1RM points with the correct trend delta")
    func exerciseSeriesFromTwoWorkouts() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let first = store.startWorkout(routineID: routineID)
        first.exercises[0].sets[0].weightKg = 60
        first.exercises[0].sets[0].reps = 8
        first.exercises[0].sets[0].isDone = true
        _ = store.finish(session: first)

        let second = store.startWorkout(routineID: routineID)
        second.exercises[0].sets[0].weightKg = 70
        second.exercises[0].sets[0].reps = 8
        second.exercises[0].sets[0].isDone = true
        _ = store.finish(session: second)

        let bundle = store.exerciseSeries(exerciseID: exercise.id, months: nil)
        #expect(bundle.e1rm.count == 2)
        #expect(bundle.volume.count == 2)
        let expectedFirst = OneRepMax.estimate(weight: 60, reps: 8) ?? 0
        let expectedSecond = OneRepMax.estimate(weight: 70, reps: 8) ?? 0
        #expect(abs(bundle.e1rmTrendDeltaKg - (expectedSecond - expectedFirst)) < 0.001)
        #expect(bundle.mostCommonWeight != nil)
    }

    @Test("exerciseSeries is empty for an exercise with no finished workouts")
    func exerciseSeriesEmpty() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let bundle = store.exerciseSeries(exerciseID: exercise.id, months: nil)
        #expect(bundle.e1rm.isEmpty)
        #expect(bundle.e1rmTrendDeltaKg == 0)
    }

    @Test("bodySeries reports this week's volume, sets and workout count")
    func bodySeriesThisWeek() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Row", primary: [.lats], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].weightKg = 80
        session.exercises[0].sets[0].reps = 10
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        let bundle = store.bodySeries(weeks: 8)
        #expect(bundle.thisWeek.workouts == 1)
        #expect(bundle.thisWeek.sets == 1)
        #expect(bundle.thisWeek.volumeKg == 800)
        #expect(bundle.setsPerMuscle[.lats] == 1)
    }
}
