import Foundation
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("HealthInsightsService")
struct HealthInsightsServiceTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeService(
        store: WorkoutStore, preferences: Preferences, health: FakeHealthStore
    ) -> HealthInsightsService {
        HealthInsightsService(healthStore: health, workoutStore: store, preferences: preferences)
    }

    // MARK: - Bodyweight day-level merge

    @Test("mergeBodyweightSeries prefers the manual entry when both sources cover the same day")
    func mergePrefersManualOnSameDay() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let manual = [
            BodyMeasurementInfo(id: UUID(), date: day.addingTimeInterval(3_600), kg: 80, source: "manual")
        ]
        let health = [HealthSample(date: day.addingTimeInterval(7_200), value: 79.5)]

        let merged = HealthInsightsService.mergeBodyweightSeries(
            manual: manual, health: health, calendar: calendar
        )

        #expect(merged.count == 1)
        #expect(merged[0].kg == 80)
        #expect(merged[0].source == "manual")
    }

    @Test("mergeBodyweightSeries keeps both readings when they land on different days")
    func mergeKeepsDistinctDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let manual = [BodyMeasurementInfo(id: UUID(), date: today, kg: 80, source: "manual")]
        let health = [HealthSample(date: yesterday, value: 81)]

        let merged = HealthInsightsService.mergeBodyweightSeries(
            manual: manual, health: health, calendar: calendar
        )

        #expect(merged.count == 2)
        #expect(merged.contains { $0.kg == 80 && $0.source == "manual" })
        #expect(merged.contains { $0.kg == 81 && $0.source == "health" })
    }

    @Test("mergeBodyweightSeries never double-plots a weight we wrote to Health ourselves")
    func mergeNeverDoublePlotsOurOwnWrite() {
        // A manual entry we pushed to Health lands back as a Health sample on the same day, with
        // a slightly different timestamp — the merge must still collapse it to one point.
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date()).addingTimeInterval(8 * 3_600)
        let manual = [BodyMeasurementInfo(id: UUID(), date: day, kg: 82.5, source: "manual")]
        let health = [HealthSample(date: day.addingTimeInterval(60), value: 82.5)]

        let merged = HealthInsightsService.mergeBodyweightSeries(
            manual: manual, health: health, calendar: calendar
        )

        #expect(merged.count == 1)
    }

    @Test("mergedBodyweightSeries is manual-only when the sync toggle is off")
    func mergedSeriesManualOnlyWhenToggleOff() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthSyncBodyweight = false
        store.logBodyweight(kg: 80, source: "manual")
        let health = FakeHealthStore()
        await health.setBodyMassHistoryToReturn([HealthSample(date: Date(), value: 79)])
        let service = makeService(store: store, preferences: preferences, health: health)

        let series = await service.mergedBodyweightSeries()

        #expect(series.count == 1)
        #expect(series[0].kg == 80)
    }

    // MARK: - Section visibility

    @Test("bodyComposition is nil when the preference is off, even with data available")
    func bodyCompositionHiddenWhenToggleOff() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthReadBodyComposition = false
        let health = FakeHealthStore()
        await health.setBodyFatToReturn(HealthSample(date: Date(), value: 18))
        let service = makeService(store: store, preferences: preferences, health: health)

        let composition = await service.bodyComposition()

        #expect(composition == nil)
    }

    @Test("bodyComposition is nil when the preference is on but Health has nothing")
    func bodyCompositionHiddenWhenEmpty() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthReadBodyComposition = true
        let health = FakeHealthStore()
        let service = makeService(store: store, preferences: preferences, health: health)

        let composition = await service.bodyComposition()

        #expect(composition == nil)
    }

    @Test("bodyComposition surfaces data once the preference is on and Health has a reading")
    func bodyCompositionShowsWhenAvailable() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthReadBodyComposition = true
        let health = FakeHealthStore()
        await health.setBodyFatToReturn(HealthSample(date: Date(), value: 18))
        let service = makeService(store: store, preferences: preferences, health: health)

        let composition = await service.bodyComposition()

        #expect(composition?.bodyFat?.value == 18)
    }

    @Test("recoverySignals is nil when the recovery preference is off")
    func recoverySignalsHiddenWhenToggleOff() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthReadRecovery = false
        let health = FakeHealthStore()
        await health.setRecoverySamples(restingHeartRate: [HealthSample(date: Date(), value: 58)])
        let service = makeService(store: store, preferences: preferences, health: health)

        let signals = await service.recoverySignals()

        #expect(signals == nil)
    }

    @Test("recoverySignals is nil when the preference is on but Health has nothing")
    func recoverySignalsHiddenWhenEmpty() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthReadRecovery = true
        let health = FakeHealthStore()
        let service = makeService(store: store, preferences: preferences, health: health)

        let signals = await service.recoverySignals()

        #expect(signals == nil)
    }

    // MARK: - External workout import

    @Test("importing external workouts twice imports once")
    func importingTwiceImportsOnce() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        let health = FakeHealthStore()
        let external = HealthExternalWorkout(
            uuid: "hk-insights-1", start: Date().addingTimeInterval(-3_600), end: Date(),
            title: "Strength Training"
        )
        await health.setExternalWorkoutsToReturn([external])
        let service = makeService(store: store, preferences: preferences, health: health)

        let firstImport = await service.importPendingExternalWorkouts()
        let secondImport = await service.importPendingExternalWorkouts()

        #expect(firstImport.count == 1)
        #expect(secondImport.isEmpty)
        #expect(store.hasWorkout(healthKitID: "hk-insights-1"))
    }

    @Test("pendingExternalWorkouts is empty once everything has been imported")
    func pendingWorkoutsEmptiesAfterImport() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = true
        let health = FakeHealthStore()
        let external = HealthExternalWorkout(
            uuid: "hk-insights-2", start: Date().addingTimeInterval(-3_600), end: Date(),
            title: "Strength Training"
        )
        await health.setExternalWorkoutsToReturn([external])
        let service = makeService(store: store, preferences: preferences, health: health)

        #expect(await service.pendingExternalWorkouts().count == 1)
        await service.importPendingExternalWorkouts()
        #expect(await service.pendingExternalWorkouts().isEmpty)
    }

    @Test("pendingExternalWorkouts is empty when the import preference is off")
    func pendingWorkoutsEmptyWhenToggleOff() async throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.healthImportWorkouts = false
        let health = FakeHealthStore()
        await health.setExternalWorkoutsToReturn([
            HealthExternalWorkout(
                uuid: "hk-insights-3", start: Date(), end: Date(), title: "Strength Training"
            )
        ])
        let service = makeService(store: store, preferences: preferences, health: health)

        #expect(await service.pendingExternalWorkouts().isEmpty)
    }
}
