import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// `ConsistencyWidget`'s data path: the snapshot's per-day sets survive the App Group, old
/// snapshots still decode, and `consistency(weeks:on:)` lays a known set of dates out the way
/// the Progress tab would.
@Suite("Widget consistency")
struct WidgetConsistencyTests {
    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar().date(from: components) ?? Date()
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 91 days ending Wednesday 2026-01-07 (Monday-first): sets on Mon 5th, Wed 7th, and on Mon
    /// 13 Oct 2025 — the first day of a 13-week window ending that Wednesday — nothing else.
    private static func snapshot(updatedAt: Date = date(2026, 1, 7)) -> WidgetSnapshot {
        let calendar = calendar()
        let wednesday = date(2026, 1, 7)
        let firstDay = calendar.date(byAdding: .day, value: -90, to: wednesday) ?? wednesday
        let start = calendar.startOfDay(for: firstDay)
        var sets = Array(repeating: 0, count: 91)
        sets[4] = 4 // Mon 13 Oct
        sets[88] = 12 // Mon 5 Jan
        sets[90] = 6 // Wed 7 Jan
        return WidgetSnapshot(
            routineName: nil, exerciseCount: 0, streakWeeks: 0, trainedDays: [], updatedAt: updatedAt,
            weekStartsMonday: true, dailySetsStart: start, dailySets: sets, weekVolumeKg: 1_234,
            weightUnit: "lb", colorBlindHeatmaps: true
        )
    }

    @Test("the per-day sets, unit and colour-blind flag round trip through the App Group")
    func roundTripsNewFields() {
        let suite = makeSuite(#function)
        let snapshot = Self.snapshot()

        WidgetSnapshotStore.write(snapshot, to: suite)
        let read = WidgetSnapshotStore.read(from: suite)

        #expect(read == snapshot)
        #expect(read.dailySets.count == 91)
        #expect(read.weightUnit == "lb")
        #expect(read.colorBlindHeatmaps)
    }

    @Test("a snapshot written before the heatmap fields existed still decodes, with defaults")
    func legacySnapshotDecodesWithDefaults() {
        let suite = makeSuite(#function)
        let legacyJSON = """
        {"routineName":"Push Day A","exerciseCount":5,"streakWeeks":3,
        "trainedDays":[true,false,true,true,false,false,true],"updatedAt":1000,"workoutDays":[1000]}
        """
        suite.set(Data(legacyJSON.utf8), forKey: "widgetSnapshot")

        let read = WidgetSnapshotStore.read(from: suite)
        #expect(read.routineName == "Push Day A")
        #expect(read.dailySetsStart == nil)
        #expect(read.dailySets.isEmpty)
        #expect(read.weekVolumeKg == 0)
        #expect(read.weightUnit == "kg")
        #expect(!read.colorBlindHeatmaps)
    }

    @Test("13 weeks of known dates become 13 week columns shaded like the Progress tab")
    func gridFromKnownDates() throws {
        let consistency = Self.snapshot().consistency(weeks: 13, on: Self.date(2026, 1, 7))

        #expect(consistency.grid.count == 13)
        #expect(consistency.totalDays == 87) // Mon 13 Oct … Wed 7 Jan
        #expect(consistency.trainedDays == 3)
        // Monday-first: the last column is Mon 5 … Sun 11 Jan; Thursday onward is the future.
        let lastWeek = try #require(consistency.grid.last)
        #expect(lastWeek[0]?.sets == 12)
        #expect(lastWeek[0]?.level == 4) // the busiest day in the window
        #expect(lastWeek[1]?.sets == 0)
        #expect(lastWeek[2]?.sets == 6)
        #expect(lastWeek[2]?.level == 3) // 6 of 12 → the 50–75 % band
        #expect(lastWeek[3] == nil)
        let firstWeek = try #require(consistency.grid.first)
        #expect(firstWeek[0]?.sets == 4)
        #expect(firstWeek[0]?.level == 2) // 4 of 12 → the 25–50 % band
        #expect(consistency.thisWeek == [true, false, true, false, false, false, false])
        #expect(consistency.thisWeekWorkouts == 2)
        #expect(consistency.thisWeekSets == 18)
        #expect(consistency.weekVolumeKg == 1_234)
    }

    @Test("the accessibility label sums the period and the week")
    func accessibilityLabel() {
        let consistency = Self.snapshot().consistency(weeks: 13, on: Self.date(2026, 1, 7))
        #expect(consistency.accessibilityLabel == "Trained 3 of 87 days, 2 this week")
        #expect(WidgetSnapshot.empty.consistency(weeks: 13, on: .now).accessibilityLabel
            == "Trained 0 of 0 days, 0 this week")
    }

    @Test("an entry in a later week drops the stale weekly volume and counts the new week from zero")
    func nextWeekEntry() {
        let nextMonday = Self.date(2026, 1, 12)
        let consistency = Self.snapshot().consistency(weeks: 13, on: nextMonday)

        #expect(consistency.weekVolumeKg == nil)
        #expect(consistency.thisWeekWorkouts == 0)
        // The window slid a week: 13 Oct dropped out, 5 and 7 Jan remain.
        #expect(consistency.trainedDays == 2)
        #expect(consistency.grid.count == 13)
        #expect(consistency.totalDays == 85)
    }

    @Test("a snapshot with only workoutDays (pre-heatmap build) still shades those days")
    func workoutDaysFallback() throws {
        let monday = Self.date(2026, 1, 5, hour: 0)
        let snapshot = WidgetSnapshot(
            routineName: nil, exerciseCount: 0, streakWeeks: 0, trainedDays: [],
            updatedAt: Self.date(2026, 1, 7), workoutDays: [monday], weekStartsMonday: true
        )
        let consistency = snapshot.consistency(weeks: 13, on: Self.date(2026, 1, 7))

        #expect(consistency.trainedDays == 1)
        #expect(try #require(consistency.grid.last)[0]?.level == 4)
    }

    @Test("the writer fills dailySets from the store's counted sets, 26 weeks ending today")
    @MainActor
    func writerFillsDailySets() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container))
        let preferences = Preferences(suite: makeSuite(#function + "prefs"))
        preferences.colorBlindHeatmaps = true
        let exercise = store.createCustomExercise(
            name: "Row", primary: [.lats], equipment: "Cable", style: .weightReps
        )
        let session = store.startFreestyle()
        session.exercises.append(store.autoFilledEntry(for: exercise))
        session.exercises[0].sets[0].weightKg = 40
        session.exercises[0].sets[0].reps = 10
        session.exercises[0].sets[0].isDone = true
        _ = store.finish(session: session)

        let now = Date()
        let snapshot = WidgetSnapshotWriter.snapshot(store: store, preferences: preferences, now: now)

        #expect(snapshot.dailySets.count == WidgetSnapshot.maxConsistencyDays)
        #expect(snapshot.dailySets.last == 1)
        #expect(snapshot.dailySets.dropLast().allSatisfy { $0 == 0 })
        let start = try #require(snapshot.dailySetsStart)
        let calendar = preferences.trainingCalendar
        let expectedStart = calendar.date(byAdding: .day, value: -181, to: calendar.startOfDay(for: now))
        #expect(start == expectedStart)
        #expect(snapshot.weekVolumeKg == 400)
        #expect(snapshot.colorBlindHeatmaps)
        #expect(snapshot.weightUnit == preferences.weightUnit.rawValue)
    }
}
