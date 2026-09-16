import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("HealthSyncService")
struct HealthSyncServiceTests {
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

    @Test("pushBodyweight sends the measurement's own date, not a fresh one")
    func pushBodyweightUsesMeasurementDate() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = true
        let health = FakeHealthStore()
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        let logged = store.logBodyweight(kg: 81.5, source: "manual")
        await service.pushBodyweight(kg: 81.5, date: logged.date)

        let pushed = await health.savedBodyMasses
        #expect(pushed.count == 1)
        #expect(pushed[0].date == logged.date)
    }

    @Test("pushBodyweight is a no-op when the bodyweight toggle is off")
    func pushBodyweightToggleOff() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = false
        let health = FakeHealthStore()
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.pushBodyweight(kg: 81.5, date: Date())

        #expect(await health.savedBodyMasses.isEmpty)
    }

    @Test("pullExternalWorkouts imports each external workout once, never a duplicate")
    func pullExternalWorkoutsDedupes() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        let health = FakeHealthStore()
        let external = HealthExternalWorkout(
            uuid: "hk-external-1", start: Date().addingTimeInterval(-3_600), end: Date(),
            title: "Strength Training"
        )
        await health.setExternalWorkoutsToReturn([external])
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.pullExternalWorkouts()
        await service.pullExternalWorkouts()

        #expect(store.hasWorkout(healthKitID: "hk-external-1"))
        #expect(store.importedHealthWorkouts().count == 1)
        // And nothing HealthKit-derived landed in the CloudKit-mirrored main store.
        #expect(store.history().count == 1)
        #expect(store.workoutsWithHealthKitID("hk-external-1").isEmpty)
    }

    @Test("pullExternalWorkouts never imports a workout that already carries our own healthKitID")
    func pullExternalWorkoutsSkipsOwnWorkouts() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        let health = FakeHealthStore()
        let ours = try finishedWorkout(store: store)
        ours.healthKitID = "hk-ours-1"
        store.save()
        // HealthKitStore filters out our own writes (DaGymWorkoutID metadata) before this ever
        // reaches HealthSyncService, so the fake only ever returns genuinely external samples —
        // but it must still refuse one whose uuid happens to already be recorded (belt-and-braces).
        let collision = HealthExternalWorkout(uuid: "hk-ours-1", start: Date(), end: Date(), title: "X")
        await health.setExternalWorkoutsToReturn([collision])
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.pullExternalWorkouts()

        #expect(store.workoutsWithHealthKitID("hk-ours-1").count == 1)
        #expect(store.importedHealthWorkouts().isEmpty)
    }
}

@Suite("HealthUnitConversion")
struct HealthUnitConversionTests {
    @Test("bodyFatPercent converts HealthKit's 0...1 fraction to a display percentage")
    func bodyFatFractionToPercent() {
        #expect(HealthUnitConversion.bodyFatPercent(fromFraction: 0.183) == 18.3)
        #expect(HealthUnitConversion.bodyFatPercent(fromFraction: 0) == 0)
    }

    @Test("a body fat reading outside 0...100 is refused rather than shown")
    func bodyFatPlausibility() {
        #expect(HealthUnitConversion.isPlausibleBodyFatPercent(18.3))
        #expect(HealthUnitConversion.isPlausibleBodyFatPercent(100))
        // A scale writing 18 into a 0...1 field reads back as 1800%.
        #expect(!HealthUnitConversion.isPlausibleBodyFatPercent(1_800))
        #expect(!HealthUnitConversion.isPlausibleBodyFatPercent(0))
        #expect(!HealthUnitConversion.isPlausibleBodyFatPercent(-3))
    }

    @Test("estimatedActiveEnergyKcal uses net METs, so it no longer over-reports by ~25%")
    func estimatedEnergyUsesNetMETs() {
        // Active energy is energy above resting (1 MET), so resistance training's 5 METs
        // contributes 4: 4 * 80kg * 1 hour = 320 kcal, not the 400 the gross figure gave.
        #expect(
            HealthUnitConversion.estimatedActiveEnergyKcal(durationSeconds: 3_600, bodyweightKg: 80) == 320
        )
        // Half the duration halves the estimate.
        #expect(
            HealthUnitConversion.estimatedActiveEnergyKcal(durationSeconds: 1_800, bodyweightKg: 80) == 160
        )
    }

    @Test("estimatedActiveEnergyKcal writes nothing rather than a zero or nonsense sample")
    func estimatedEnergyRefusesNonsense() {
        #expect(HealthUnitConversion.estimatedActiveEnergyKcal(durationSeconds: -10, bodyweightKg: -5) == nil)
        #expect(HealthUnitConversion.estimatedActiveEnergyKcal(durationSeconds: 0, bodyweightKg: 80) == nil)
        let noWeight = HealthUnitConversion.estimatedActiveEnergyKcal(
            durationSeconds: 3_600, bodyweightKg: 0
        )
        #expect(noWeight == nil)
        // 4 * 80 * (10/3600) = 0.89 kcal — under 1, so not worth a sample.
        #expect(HealthUnitConversion.estimatedActiveEnergyKcal(durationSeconds: 10, bodyweightKg: 80) == nil)
    }
}
