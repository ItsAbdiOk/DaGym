import Foundation
import Testing

@testable import DaGym

@Suite("Widget snapshot persistence")
struct WidgetSnapshotTests {
    /// A fresh, isolated `UserDefaults` suite per test (mirrors `PreferencesTests`).
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("encodes and decodes round trip through an isolated UserDefaults suite")
    func roundTrips() throws {
        let suite = makeSuite(#function)
        let snapshot = WidgetSnapshot(
            routineName: "Push Day A", exerciseCount: 5, streakWeeks: 3,
            trainedDays: [true, false, true, true, false, false, true],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        WidgetSnapshotStore.write(snapshot, to: suite)
        let read = WidgetSnapshotStore.read(from: suite)

        #expect(read == snapshot)
    }

    @Test("a rest-day snapshot (nil routine name) round trips too")
    func roundTripsRestDay() throws {
        let suite = makeSuite(#function)
        let snapshot = WidgetSnapshot(
            routineName: nil, exerciseCount: 0, streakWeeks: 0,
            trainedDays: Array(repeating: false, count: 7), updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        WidgetSnapshotStore.write(snapshot, to: suite)
        #expect(WidgetSnapshotStore.read(from: suite) == snapshot)
    }

    @Test("reading an empty suite returns the documented empty snapshot")
    func emptySuiteReadsEmpty() throws {
        let suite = makeSuite(#function)
        #expect(WidgetSnapshotStore.read(from: suite) == WidgetSnapshot.empty)
    }
}
