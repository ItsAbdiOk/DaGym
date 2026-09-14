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

    @Test("pullBodyweightHistory maps every new Health sample, skipping ones already stored")
    func pullBodyweightHistoryMapsSamples() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = true
        let health = FakeHealthStore()
        let existingDate = Date().addingTimeInterval(-86_400 * 10)
        store.logBodyweight(kg: 80, date: existingDate, source: "health")
        let newDate = Date().addingTimeInterval(-86_400 * 5)
        await health.setBodyMassHistoryToReturn([
            HealthSample(date: existingDate, value: 80), HealthSample(date: newDate, value: 79.2)
        ])
        let service = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await service.pullBodyweightHistory()

        let series = store.bodyweightSeries(days: 365)
        #expect(series.count == 2)
        #expect(series.contains { $0.date == newDate && $0.kg == 79.2 && $0.source == "health" })
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
        let matching = store.workoutsWithHealthKitID("hk-external-1")
        #expect(matching.count == 1)
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
    }
}

private extension WorkoutStore {
    /// Test-only: every `WorkoutModel` carrying this `HKWorkout` uuid, so a dedupe test can
    /// assert there's exactly one rather than just that `hasWorkout` returns true.
    func workoutsWithHealthKitID(_ id: String) -> [WorkoutModel] {
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.healthKitID == id })
        return (try? context.fetch(descriptor)) ?? []
    }
}

@Suite("HealthUnitConversion")
struct HealthUnitConversionTests {
    @Test("bodyFatPercent converts HealthKit's 0...1 fraction to a display percentage")
    func bodyFatFractionToPercent() {
        #expect(HealthUnitConversion.bodyFatPercent(fromFraction: 0.183) == 18.3)
        #expect(HealthUnitConversion.bodyFatPercent(fromFraction: 0) == 0)
    }

    @Test("estimatedActiveEnergyKcal scales with bodyweight and duration")
    func estimatedEnergyScalesCorrectly() {
        // 5 METs * 80kg * 1 hour = 400 kcal.
        let oneHour = HealthUnitConversion.estimatedActiveEnergyKcal(
            durationSeconds: 3_600, bodyweightKg: 80
        )
        #expect(oneHour == 400)
        // Half the duration halves the estimate.
        let halfHour = HealthUnitConversion.estimatedActiveEnergyKcal(
            durationSeconds: 1_800, bodyweightKg: 80
        )
        #expect(halfHour == 200)
    }

    @Test("estimatedActiveEnergyKcal never goes negative on bad input")
    func estimatedEnergyClampsNegatives() {
        let value = HealthUnitConversion.estimatedActiveEnergyKcal(durationSeconds: -10, bodyweightKg: -5)
        #expect(value == 0)
    }
}
