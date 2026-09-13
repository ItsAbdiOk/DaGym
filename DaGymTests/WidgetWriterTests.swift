import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Widget snapshot writer")
struct WidgetWriterTests {
    /// Counts `reloadTimelines` calls (a reference so the writer's closure can bump it).
    private final class ReloadCounter {
        var count = 0
        var isEmpty: Bool { count == 0 }
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Wednesday 2026-01-07, mid-morning.
    private static func wednesday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 7
        components.hour = 10
        return calendar().date(from: components) ?? Date()
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeRoutine(_ store: WorkoutStore, name: String) -> RoutineInfo {
        let exercise = store.createCustomExercise(
            name: "\(name) Exercise", primary: [.chest], equipment: "Barbell", style: .weightReps
        )
        let draft = RoutineExerciseDraft(
            exerciseID: exercise.id, sets: [PlannedSetDraft(kind: .working, targetReps: 8)]
        )
        return store.saveRoutine(id: nil, name: name, exercises: [draft])
    }

    @Test("the snapshot names the scheduled routine, not the first one, and Rest Day off-schedule")
    func snapshotFollowsSchedule() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function + "prefs"))
        _ = makeRoutine(store, name: "Aardvark Day")
        let legs = makeRoutine(store, name: "Legs")
        var schedule = WeeklySchedule()
        schedule.days[.wednesday] = legs.id
        store.saveSchedule(schedule)

        let wednesday = Self.wednesday()
        let thursday = try #require(Self.calendar().date(byAdding: .day, value: 1, to: wednesday))

        let midweek = WidgetSnapshotWriter.snapshot(store: store, preferences: preferences, now: wednesday)
        #expect(midweek.routineName == "Legs")
        #expect(midweek.exerciseCount == 1)

        let rest = WidgetSnapshotWriter.snapshot(store: store, preferences: preferences, now: thursday)
        #expect(rest.routineName == nil)
        #expect(rest.exerciseCount == 0)
    }

    @Test("the writer is a no-op in a test process")
    func noOpUnderTesting() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function + "prefs"))
        let suite = makeSuite(#function)
        _ = makeRoutine(store, name: "Push A")
        let reloads = ReloadCounter()
        let writer = WidgetSnapshotWriter(
            suite: suite, isTesting: LaunchFlags.isTesting, reloadTimelines: { reloads.count += 1 }
        )

        writer.refresh(store: store, preferences: preferences)

        #expect(LaunchFlags.isTesting)
        #expect(WidgetSnapshotStore.read(from: suite) == .empty)
        #expect(reloads.isEmpty)
    }

    @Test("outside tests it writes the injected suite and reloads only when the content changed")
    func writesAndReloadsOnChange() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function + "prefs"))
        let suite = makeSuite(#function)
        let push = makeRoutine(store, name: "Push A")
        var schedule = WeeklySchedule()
        schedule.days[.wednesday] = push.id
        store.saveSchedule(schedule)
        let reloads = ReloadCounter()
        let writer = WidgetSnapshotWriter(
            suite: suite, isTesting: false, reloadTimelines: { reloads.count += 1 }
        )
        let wednesday = Self.wednesday()

        writer.refresh(store: store, preferences: preferences, now: wednesday)
        #expect(WidgetSnapshotStore.read(from: suite).routineName == "Push A")
        #expect(reloads.count == 1)

        writer.refresh(store: store, preferences: preferences, now: wednesday.addingTimeInterval(60))
        #expect(reloads.count == 1)

        schedule.days[.wednesday] = nil
        schedule.days[.thursday] = push.id
        store.saveSchedule(schedule)
        writer.refresh(store: store, preferences: preferences, now: wednesday)
        #expect(WidgetSnapshotStore.read(from: suite).routineName == nil)
        #expect(reloads.count == 2)
    }
}
