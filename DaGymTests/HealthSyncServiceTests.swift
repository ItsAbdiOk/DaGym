import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("HealthSyncService")
struct HealthSyncServiceTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A finished workout with one completed working set, for the sync tests below.
    private func finishedWorkout(store: WorkoutStore) throws -> WorkoutModel {
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        let routine = store.saveRoutine(id: nil, name: "Push A", exercises: [draft])
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
        let workoutID = try #require(session.workoutID)
        return try #require(store.workout(id: workoutID))
    }

    @Test("finish syncs one workout with correct duration and metadata")
    func syncsFinishedWorkout() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthWriteWorkouts = true
        let health = FakeHealthStore()
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        let workout = try finishedWorkout(store: store)
        await service.syncFinishedWorkout(workout)

        let saved = await health.savedWorkouts
        #expect(saved.count == 1)
        #expect(saved[0].workoutID == workout.id.uuidString)
        #expect(saved[0].setCount == 1)
        #expect(saved[0].volumeKg == 480)
        #expect(workout.healthKitID != nil)
    }

    @Test("a second sync of the same workout never duplicates it")
    func noDuplicateOnSecondSync() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthWriteWorkouts = true
        let health = FakeHealthStore()
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        let workout = try finishedWorkout(store: store)
        await service.syncFinishedWorkout(workout)
        await service.syncFinishedWorkout(workout)

        let saved = await health.savedWorkouts
        #expect(saved.count == 1)
    }

    @Test("toggle off writes nothing")
    func toggleOffWritesNothing() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthWriteWorkouts = false
        let health = FakeHealthStore()
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        let workout = try finishedWorkout(store: store)
        await service.syncFinishedWorkout(workout)

        let saved = await health.savedWorkouts
        #expect(saved.isEmpty)
        #expect(workout.healthKitID == nil)
    }

    @Test("pullBodyweight creates one measurement when Health has a newer reading")
    func pullBodyweightCreatesMeasurement() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = true
        let health = FakeHealthStore()
        await health.setBodyMassToReturn(HealthBodyMass(kg: 81.5, date: Date()))
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.pullBodyweight()

        let measurement = try #require(store.latestBodyMeasurement())
        #expect(measurement.bodyweightKg == 81.5)
        #expect(measurement.source == "health")
    }

    @Test("pullBodyweight is a no-op when the toggle is off")
    func pullBodyweightToggleOff() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = false
        let health = FakeHealthStore()
        await health.setBodyMassToReturn(HealthBodyMass(kg: 81.5, date: Date()))
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.pullBodyweight()

        #expect(store.latestBodyMeasurement() == nil)
    }
}
