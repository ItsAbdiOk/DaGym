import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// Regression cover for the Apple Health defects found after commit 21dd63d: the duplicated
/// weigh-in, the deleted import that came straight back, the observer that signalled "done"
/// before it had done anything, and HealthKit-derived rows landing in the CloudKit-mirrored
/// store.
@MainActor
@Suite("Apple Health import and sync regressions")
struct HealthImportTombstoneTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func external(_ uuid: String, hoursAgo: Double = 1) -> HealthExternalWorkout {
        let end = Date().addingTimeInterval(-hoursAgo * 3_600)
        return HealthExternalWorkout(
            uuid: uuid, start: end.addingTimeInterval(-3_600), end: end, title: "Strength Training"
        )
    }

    // MARK: - A manual weigh-in that DaGym pushes to Health comes back as one reading, not two

    @Test("a manual weigh-in pushed to Health plots once, not twice")
    func manualWeighInIsNotDuplicatedByItsOwnPush() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = true
        let health = FakeHealthStore()
        let sync = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)
        let insights = HealthInsightsService(
            healthStore: health, workoutStore: store, preferences: preferences
        )

        // Log manually, then push exactly that row (its own date) to Health.
        let logged = store.logBodyweight(kg: 81.5, source: "manual")
        await sync.pushBodyweight(kg: 81.5, date: logged.date)

        // Health now hands that sample straight back, the way the body-mass observer used to.
        let pushed = await health.savedBodyMasses
        #expect(pushed.count == 1)
        await health.setBodyMassHistoryToReturn(pushed.map { HealthSample(date: $0.date, value: $0.kg) })

        let series = await insights.mergedBodyweightSeries()
        #expect(series.count == 1)
        #expect(series[0].source == "manual")
        // And nothing HealthKit-derived was written into the CloudKit-mirrored store.
        #expect(store.recentBodyMeasurements().allSatisfy { $0.source == "manual" })
    }

    @Test("a Health sample a fraction of a second off the manual row still folds into one point")
    func nearlyIdenticalTimestampsStillFold() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = true
        let health = FakeHealthStore()
        let insights = HealthInsightsService(
            healthStore: health, workoutStore: store, preferences: preferences
        )

        // The exact failure the old `Set<Date>` dedupe had: a timestamp that round-tripped
        // through SQLite and HealthKit and came back a hair different.
        let logged = store.logBodyweight(kg: 80, source: "manual")
        await health.setBodyMassHistoryToReturn([
            HealthSample(date: logged.date.addingTimeInterval(0.0004), value: 80)
        ])

        let series = await insights.mergedBodyweightSeries()
        #expect(series.count == 1)
    }

    // MARK: - A deleted import stays deleted

    @Test("deleting an imported workout tombstones it so the next pull can't bring it back")
    func deletedImportStaysDeleted() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        let health = FakeHealthStore()
        let sample = external("hk-tombstone-1")
        await health.setExternalWorkoutsToReturn([sample])
        let sync = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await sync.pullExternalWorkouts()
        let imported = try #require(store.importedHealthWorkouts().first)
        #expect(store.history().count == 1)

        store.deleteWorkout(id: imported.id)
        #expect(store.importedHealthWorkouts().isEmpty)
        #expect(store.isIgnoredHealthWorkout(healthKitID: sample.uuid))

        // Health still reports the sample. It must not come back.
        await sync.pullExternalWorkouts()
        #expect(store.importedHealthWorkouts().isEmpty)
        #expect(store.history().isEmpty)
    }

    @Test("a tombstoned workout is no longer offered as pending")
    func tombstonedWorkoutIsNotPending() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        let health = FakeHealthStore()
        let sample = external("hk-tombstone-2")
        await health.setExternalWorkoutsToReturn([sample])
        let insights = HealthInsightsService(
            healthStore: health, workoutStore: store, preferences: preferences
        )

        let imported = await insights.importPendingExternalWorkouts()
        store.deleteWorkout(id: try #require(imported.first).id)

        let pending = await insights.pendingExternalWorkouts()
        #expect(pending.isEmpty)
    }

    @Test("undoing the delete puts the import back and lifts the tombstone")
    func undoRestoresTheImport() async throws {
        let store = try makeStore()
        let sample = external("hk-tombstone-3")
        let imported = try #require(store.importExternalWorkout(sample))
        let id = imported.id

        let snapshot = try #require(store.deleteWorkout(id: id))
        store.restoreWorkout(snapshot)

        #expect(store.importedHealthWorkouts().count == 1)
        #expect(store.importedHealthWorkout(id: id) != nil)
        #expect(!store.isIgnoredHealthWorkout(healthKitID: sample.uuid))
    }

    // MARK: - Observer

    @Test("a Health change delivered to the registered observer imports the new session")
    func observerImportsOnDelivery() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        preferences.healthAutoImportWorkouts = true
        let health = FakeHealthStore()
        await health.setExternalWorkoutsToReturn([external("hk-observer-1")])
        let sync = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await sync.startObservingHealthChanges()
        let registered = await health.workoutObserverRegistered
        #expect(registered)

        let fired = await health.triggerWorkoutChange()
        #expect(fired)
        #expect(store.importedHealthWorkouts().count == 1)
    }

    /// There is no way to un-register a live `HKObserverQuery`, so the toggles have to be
    /// re-read on every delivery. Before that, the observer kept importing until the next
    /// relaunch after "Import automatically" was switched off.
    @Test("turning automatic import off after registration stops the observer importing")
    func observerHonoursAToggleFlippedAfterRegistration() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        preferences.healthAutoImportWorkouts = true
        let health = FakeHealthStore()
        await health.setExternalWorkoutsToReturn([external("hk-observer-2")])
        let sync = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)
        await sync.startObservingHealthChanges()

        preferences.healthAutoImportWorkouts = false
        let fired = await health.triggerWorkoutChange()

        #expect(fired)
        #expect(store.importedHealthWorkouts().isEmpty)
    }

    @Test("the background observer is not registered until the user opts into automatic import")
    func observerNeedsTheExplicitOptIn() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        preferences.healthAutoImportWorkouts = false
        let health = FakeHealthStore()
        let sync = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)

        await sync.startObservingHealthChanges()

        let registered = await health.workoutObserverRegistered
        #expect(!registered)
    }

    // MARK: - Deleting a workout deletes what we wrote to Health

    @Test("deleting a workout DaGym wrote to Health deletes the HKWorkout too")
    func deletingAWorkoutDeletesOurHealthSample() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthWriteWorkouts = true
        let health = FakeHealthStore()
        let sync = HealthSyncService(healthStore: health, workoutStore: store, preferences: preferences)
        sync.bind(to: store)

        let workout = WorkoutModel(
            title: "Push A", startedAt: Date().addingTimeInterval(-3_600), endedAt: Date()
        )
        store.context.insert(workout)
        store.save()
        await sync.syncFinishedWorkout(workout)
        let hkID = try #require(workout.healthKitID)

        store.deleteWorkout(id: workout.id)
        // The hook fires a detached Task; give it a turn of the main actor to run.
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        let deleted = await health.deletedWorkoutIDs
        #expect(deleted == [hkID])
    }

    // MARK: - The legacy-store repair

    @Test("HealthKit-derived rows written by the old build are moved out of the main store")
    func legacyHealthRowsArePurgedFromTheMainStore() throws {
        let store = try makeStore()
        let stray = WorkoutModel(
            title: "Strength Training", startedAt: Date().addingTimeInterval(-7_200),
            endedAt: Date().addingTimeInterval(-3_600), isBackfilled: true,
            sourceDevice: "Health", healthKitID: "hk-legacy-1"
        )
        store.context.insert(stray)
        store.logBodyweight(kg: 80, source: "health")
        store.logBodyweight(kg: 81, source: "manual")
        store.save()

        let removed = store.purgeHealthDerivedRowsFromMainStore()

        #expect(removed == 2)
        #expect(store.workoutsWithHealthKitID("hk-legacy-1").isEmpty)
        #expect(store.importedHealthWorkout(healthKitID: "hk-legacy-1") != nil)
        #expect(store.recentBodyMeasurements().map(\.source) == ["manual"])
        // The imported row is still in History — the user keeps it, it just lives locally now.
        #expect(store.history().count == 1)
    }
}

extension WorkoutStore {
    /// Test-only: every `WorkoutModel` carrying this `HKWorkout` uuid, so a test can assert that
    /// HealthKit-derived rows are *not* in the CloudKit-mirrored main store.
    func workoutsWithHealthKitID(_ id: String) -> [WorkoutModel] {
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.healthKitID == id })
        return (try? context.fetch(descriptor)) ?? []
    }
}
