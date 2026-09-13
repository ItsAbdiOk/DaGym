import Foundation
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore body measurements")
struct WorkoutStoreBodyMeasurementTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    @Test("no measurements logged yet returns nil")
    func emptyReturnsNil() throws {
        let store = try makeStore()
        #expect(store.latestBodyMeasurement() == nil)
    }

    @Test("logBodyweight persists and latestBodyMeasurement returns the newest")
    func logsAndReturnsNewest() throws {
        let store = try makeStore()
        store.logBodyweight(kg: 80, date: Date().addingTimeInterval(-86_400), source: "manual")
        store.logBodyweight(kg: 81.2, date: Date(), source: "health")

        let latest = try #require(store.latestBodyMeasurement())
        #expect(latest.bodyweightKg == 81.2)
        #expect(latest.source == "health")
    }
}
