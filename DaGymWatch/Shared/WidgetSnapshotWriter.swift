import Foundation
import GymCore
import os
import SwiftData
import WidgetKit

/// The watch's stand-in for the phone's `WidgetSnapshotWriter`: the shared `WorkoutStore` calls
/// `refresh(store:)` after `finish(session:)`, `saveRoutine` and `deleteRoutine`, and here that
/// rewrites the `WatchSnapshot` the complications read. Same name and signature so the store
/// compiles unchanged on both platforms.
@MainActor
enum WidgetSnapshotWriter {
    static func refresh(store: WorkoutStore) {
        // Keeps whatever rest is on the face: a store path that runs mid-rest must not wipe
        // the countdown off the complication.
        guard let writer = WatchSnapshotWriter.writer(for: store) else { return }
        writer.refresh(rest: writer.writtenRest, rebuild: true)
    }
}

/// Builds and writes the `WatchSnapshot`, reloading the widget timelines only when the content
/// changed (WidgetKit's daily reload budget is small on the wrist).
///
/// The idle part — streak, week, next session — is fetched from the store once and cached;
/// every rest-state change (each logged set, each `+30s`, each crown detent on the full-screen
/// rest) only splices `rest` into that cache. Rebuilding on each of those used to walk the
/// whole history and every routine on the main thread in the tap-to-log path. One writer per
/// `WatchStore`, registered by its `WorkoutStore` so the store's own post-finish refresh finds
/// the cache it should rebuild.
@MainActor
final class WatchSnapshotWriter {
    private static let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

    /// The live writer for each store (weak: a test's stores come and go).
    private static var writers: [ObjectIdentifier: WeakWriter] = [:]

    private struct WeakWriter {
        weak var writer: WatchSnapshotWriter?
    }

    static func writer(for store: WorkoutStore) -> WatchSnapshotWriter? {
        writers[ObjectIdentifier(store)]?.writer
    }

    private weak var store: WorkoutStore?
    /// Where the snapshot goes: the App Group, or a throwaway suite under test. Nil (the
    /// sample store, or no App Group) makes every refresh a no-op.
    private let suite: UserDefaults?
    private let calendar: () -> Calendar
    /// The last idle snapshot built from the store. Nil until the first rebuild.
    private(set) var idle: WatchSnapshot?
    /// The rest the App Group currently holds, to tell a natural rest end (the timeline already
    /// hands back to idle on its own) from an early skip (the face must be told).
    private(set) var writtenRest: WatchSnapshot.Rest?
    /// Timelines reloaded so far — for tests, which count them rather than read WidgetKit.
    private(set) var reloadCount = 0

    init(
        store: WorkoutStore, suite: UserDefaults? = WatchSnapshotStore.appGroupSuite,
        calendar: @escaping () -> Calendar = { WatchPreferences.shared.trainingCalendar }
    ) {
        self.store = store
        self.suite = WatchLaunchFlags.isSample ? nil : suite
        self.calendar = calendar
        Self.writers[ObjectIdentifier(store)] = WeakWriter(writer: self)
    }

    /// Writes `rest` over the cached idle snapshot. `rebuild` fetches the idle part from the
    /// store first — at Home refresh, finish and any routine change — and takes `workoutDates`
    /// when the caller already has them, so a Home refresh fetches the history once.
    func refresh(
        rest: WatchSnapshot.Rest?, rebuild: Bool = false, now: Date = Date(), workoutDates: [Date]? = nil
    ) {
        guard let suite else { return }
        if rebuild, let store {
            let state = Self.signposter.beginInterval("watchSnapshot")
            idle = Self.snapshot(store: store, now: now, calendar: calendar(), workoutDates: workoutDates)
            Self.signposter.endInterval("watchSnapshot", state)
        }
        var next = idle ?? .empty
        next.rest = rest
        let current = WatchSnapshotStore.read(from: suite)
        guard next != current else { return }
        WatchSnapshotStore.write(next, to: suite)
        let previousRest = writtenRest
        writtenRest = rest
        guard Self.shouldReload(from: previousRest, to: rest, now: now) else { return }
        reloadCount += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Whether a change needs a timeline reload. A rest that ran to its end doesn't: the
    /// timeline the provider built for it already has the idle entry at `endDate`, so the two
    /// reloads per set (rest in, rest out) become one. A rest skipped early, a new rest, or any
    /// idle change (the provider has no entry for those) still reloads.
    static func shouldReload(
        from previous: WatchSnapshot.Rest?, to next: WatchSnapshot.Rest?, now: Date,
        tolerance: TimeInterval = 2
    ) -> Bool {
        guard let previous, next == nil else { return true }
        return previous.endDate.timeIntervalSince(now) > tolerance
    }

    static func snapshot(
        store: WorkoutStore, now: Date = Date(),
        calendar: Calendar = WatchPreferences.shared.trainingCalendar, workoutDates: [Date]? = nil
    ) -> WatchSnapshot {
        let dates = workoutDates ?? store.finishedWorkoutStartDates()
        let streak = Streaks.weekly(
            workoutDates: dates, weeklyGoal: WatchPreferences.weeklyGoal, calendar: calendar, now: now
        )
        var snapshot = WatchSnapshot(streakWeeks: streak.current)
        snapshot.trainedThisWeek = trainedDays(dates, calendar: calendar, now: now)
        if let today = store.todaysRoutine(calendar: calendar, now: now) {
            snapshot.nextRoutineName = today.name
            snapshot.nextSessionDate = calendar.date(
                bySettingHour: WatchPreferences.scheduledStartHour, minute: 0, second: 0, of: now
            )
            snapshot.isNextToday = true
        } else if let next = store.nextSession(calendar: calendar, now: now) {
            snapshot.nextRoutineName = next.routine.name
            snapshot.nextSessionDate = calendar.date(
                bySettingHour: WatchPreferences.scheduledStartHour, minute: 0, second: 0, of: next.date
            )
        }
        return snapshot
    }

    /// Seven flags, first weekday first, true on each day this week that had a session.
    static func trainedDays(_ dates: [Date], calendar: Calendar, now: Date) -> [Bool] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return Array(repeating: false, count: 7)
        }
        let trained = Set(dates.map { calendar.startOfDay(for: $0) })
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return false }
            return trained.contains(calendar.startOfDay(for: day))
        }
    }
}

extension WorkoutStore {
    /// `startedAt` of every finished workout, newest first — the streak and the week ring need
    /// the dates only, not every `WorkoutModel` with its exercises faulted in.
    func finishedWorkoutStartDates() -> [Date] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        var descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\.startedAt]
        return fetch(descriptor).map(\.startedAt)
    }
}
