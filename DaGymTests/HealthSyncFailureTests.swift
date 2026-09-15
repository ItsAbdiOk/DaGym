import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The paths `HealthSyncService` takes when HealthKit says no, when the lifter changes their
/// mind mid round-trip, and when a calorie estimate is asked for.
@MainActor
@Suite("HealthSyncService: failures, races and estimates")
struct HealthSyncFailureTests {
    private func makeStore() throws -> WorkoutStore {
        WorkoutStore(context: ModelContext(try ModelContainer.dagym(inMemory: true)))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func finishedWorkout(store: WorkoutStore) throws -> WorkoutModel {
        let exercise = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id,
            sets: [PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60)]
        )
        let routine = store.saveRoutine(id: nil, name: "Push", exercises: [draft])
        let session = store.startWorkout(routineID: routine.id)
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)
        let workoutID = try #require(session.workoutID)
        return try #require(store.workout(id: workoutID))
    }

    @Test("a workout deleted during the Health round-trip is removed from Health again, not orphaned")
    func deletedMidFlightIsRemovedFromHealth() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthWriteWorkouts = true
        let health = FakeHealthStore()
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)
        let workout = try finishedWorkout(store: store)
        let workoutID = workout.id
        await health.setDuringSaveWorkout { @MainActor in _ = store.deleteWorkout(id: workoutID) }

        await service.syncFinishedWorkout(workout)

        #expect(await health.savedWorkouts.count == 1)
        #expect(await health.deletedWorkoutIDs == ["fake-hk-1"])
        #expect(store.workout(id: workoutID) == nil)
        #expect(service.lastSyncDate == nil)
    }

    @Test("a failed Health write leaves the workout unsynced so the next attempt retries it")
    func failedWriteLeavesWorkoutUnsynced() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthWriteWorkouts = true
        let health = FakeHealthStore()
        await health.setErrorToThrow(HealthStoreFailure(reason: "denied"))
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)
        let workout = try finishedWorkout(store: store)

        await service.syncFinishedWorkout(workout)
        #expect(workout.healthKitID == nil)
        #expect(service.lastSyncDate == nil)

        await health.setErrorToThrow(nil)
        await service.syncFinishedWorkout(workout)
        #expect(workout.healthKitID == "fake-hk-1")
        #expect(service.lastSyncDate != nil)
    }

    @Test("a failed delete, bodyweight push or external pull is swallowed and imports nothing")
    func otherFailuresAreSwallowed() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = true
        preferences.healthImportWorkouts = true
        let health = FakeHealthStore()
        await health.setErrorToThrow(HealthStoreFailure(reason: "offline"))
        await health.setExternalWorkoutsToReturn([
            HealthExternalWorkout(uuid: "hk-x", start: Date(), end: Date(), title: "Strength")
        ])
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.deleteWorkoutFromHealth(healthKitID: "hk-gone")
        await service.pushBodyweight(kg: 80, date: Date())
        let imported = await service.pullExternalWorkouts()

        #expect(imported == 0)
        #expect(store.importedHealthWorkouts().isEmpty)
        #expect(await health.savedBodyMasses.isEmpty)
        #expect(await health.deletedWorkoutIDs.isEmpty)
        #expect(service.lastSyncDate == nil)
    }

    @Test("authorization: a refused request still refreshes the status, and finishes 'authorizing'")
    func authorizationFailureStillRefreshesStatus() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        let health = FakeHealthStore()
        await health.setErrorToThrow(HealthStoreFailure(reason: "sheet dismissed"))
        await health.setAuthorizationRequestToReturn(.shouldRequest)
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.authorize()

        #expect(await health.authorizationRequested)
        #expect(service.authorizationRequest == .shouldRequest)
        #expect(!service.isAuthorizing)
    }

    @Test("observer registration failure is swallowed; the auto-import pull still honours both toggles")
    func observerFailureAndAutoImportGate() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        preferences.healthAutoImportWorkouts = true
        let health = FakeHealthStore()
        await health.setErrorToThrow(HealthStoreFailure(reason: "no background delivery"))
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.startObservingHealthChanges()
        #expect(await health.workoutObserverRegistered == false)

        await health.setErrorToThrow(nil)
        await health.setExternalWorkoutsToReturn([
            HealthExternalWorkout(uuid: "hk-auto", start: Date(), end: Date(), title: "Strength")
        ])
        preferences.healthAutoImportWorkouts = false
        #expect(await service.pullExternalWorkoutsIfAutoImportEnabled() == 0)
        preferences.healthAutoImportWorkouts = true
        preferences.healthImportWorkouts = false
        #expect(await service.pullExternalWorkoutsIfAutoImportEnabled() == 0)
        preferences.healthImportWorkouts = true
        #expect(await service.pullExternalWorkoutsIfAutoImportEnabled() == 1)
    }

    @Test("with calorie estimates on, the write carries a net-MET estimate from the best-known bodyweight")
    func energyEstimateUsesBestKnownBodyweight() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthWriteWorkouts = true
        preferences.healthEstimateCalories = true
        let health = FakeHealthStore()
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        // No bodyweight anywhere: the generic 80 kg keeps a first-ever sync from writing nothing.
        let first = try finishedWorkout(store: store)
        first.startedAt = try #require(first.endedAt).addingTimeInterval(-3_600)
        await service.syncFinishedWorkout(first)
        let generic = try #require(await health.savedWorkouts.last)
        #expect(generic.energyIsEstimate)
        #expect(generic.energyKcal
            == HealthUnitConversion.estimatedActiveEnergyKcal(durationSeconds: 3_600, bodyweightKg: 80))

        // The workout's own recorded bodyweight beats the latest measurement.
        _ = store.logBodyweight(kg: 90)
        let second = try finishedWorkout(store: store)
        second.startedAt = try #require(second.endedAt).addingTimeInterval(-1_800)
        second.bodyweightKg = 100
        await service.syncFinishedWorkout(second)
        let own = try #require(await health.savedWorkouts.last)
        #expect(own.energyKcal
            == HealthUnitConversion.estimatedActiveEnergyKcal(durationSeconds: 1_800, bodyweightKg: 100))

        // An instant workout has no energy worth writing, and says so rather than sending 0.
        let instant = try finishedWorkout(store: store)
        instant.startedAt = try #require(instant.endedAt)
        await service.syncFinishedWorkout(instant)
        let none = try #require(await health.savedWorkouts.last)
        #expect(none.energyKcal == nil)
        #expect(!none.energyIsEstimate)
    }
}
