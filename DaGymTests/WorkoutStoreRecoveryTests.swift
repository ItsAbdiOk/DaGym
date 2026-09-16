import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore recovery + streak data")
struct WorkoutStoreRecoveryTests {
    private func makeRoutine(store: WorkoutStore, exerciseID: UUID) -> UUID {
        let draft = RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 20),
                PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)
            ]
        )
        return store.saveRoutine(id: nil, name: "Push A", exercises: [draft]).id
    }

    @Test("workoutDates returns only finished workouts' start dates")
    func workoutDatesOnlyFinished() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let finished = store.startWorkout(routineID: routineID)
        finished.exercises[0].sets[1].weightKg = 60
        finished.exercises[0].sets[1].reps = 8
        finished.exercises[0].sets[1].isDone = true
        _ = store.finish(session: finished)

        _ = store.startWorkout(routineID: routineID) // left in progress, never finished

        let dates = store.workoutDates()
        #expect(dates.count == 1)
        #expect(dates.first == finished.startedAt)
    }

    @Test("recoveryEvents emits primary and secondary events by StimulusAttribution, warm-ups excluded")
    func recoveryEventsSharesAndWarmups() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        store.fetchExerciseModel(id: exercise.id)?.secondaryMuscles = [Muscle.triceps.rawValue]
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let session = store.startWorkout(routineID: routineID)
        session.exercises[0].sets[0].isDone = true // warm-up: should not appear
        session.exercises[0].sets[1].weightKg = 60
        session.exercises[0].sets[1].reps = 8
        session.exercises[0].sets[1].isDone = true
        _ = store.finish(session: session)

        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let events = store.recoveryEvents(since: since)

        #expect(events.count == 2)
        let chestEvent = events.first { $0.muscle == .chest }
        let tricepsEvent = events.first { $0.muscle == .triceps }
        #expect(chestEvent?.share == 1.0)
        // `Recovery.secondaryShare` (0.45), not a second, hard-coded opinion of what half means —
        // the same weight the body map and the volume charts give a secondary mover.
        #expect(tricepsEvent?.share == Recovery.secondaryShare)
    }

    @Test("recoveryEvents excludes workouts started before the cutoff")
    func recoveryEventsRespectsSince() throws {
        let store = try makeStore()
        let exercise = store.createCustomExercise(
            name: "Squat", primary: [.quads], equipment: "Barbell", style: .weightReps
        )
        let routineID = makeRoutine(store: store, exerciseID: exercise.id)

        let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let old = store.startBackfill(date: oldDate, durationMinutes: 45, routineID: routineID)
        old.exercises[0].sets[1].weightKg = 100
        old.exercises[0].sets[1].reps = 5
        old.exercises[0].sets[1].isDone = true
        _ = store.finish(session: old)

        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let events = store.recoveryEvents(since: since)
        #expect(events.isEmpty)
    }
}
