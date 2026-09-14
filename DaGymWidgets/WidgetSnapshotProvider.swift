import Foundation
import WidgetKit

/// One rendered day. `snapshot` is kept alongside the resolved day so the views can read the
/// user's theme off it.
struct WidgetSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let day: ResolvedWidgetDay

    init(date: Date, snapshot: WidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
        day = snapshot.resolved(on: date)
    }
}

/// Shared `TimelineProvider` for `TodayWorkoutWidget` and `StreakWidget`. Reads the latest
/// `WidgetSnapshot` from the App Group; never touches the SwiftData store.
///
/// One entry per upcoming midnight, not a single `.never` entry. The app reloads timelines
/// whenever the snapshot changes, but it cannot reload while it isn't running — and a day passing
/// changes everything the widget shows: whose routine is "today", which 7 days the dot row covers,
/// and whether the weekly streak has lapsed. A lifter who trains Monday and doesn't open the app
/// used to still read "TODAY / Push A / 5 EXERCISES" on Wednesday.
struct WidgetSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetSnapshotEntry {
        WidgetSnapshotEntry(date: .now, snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetSnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? Self.placeholderSnapshot : current()
        completion(WidgetSnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetSnapshotEntry>) -> Void) {
        let snapshot = current()
        let entries = Self.entries(for: snapshot, now: .now)
        // `.after` the last midnight we have a plan for: WidgetKit comes back for a fresh timeline
        // exactly when this one runs out of true days to show.
        let policy: TimelineReloadPolicy = entries.last.map { .after($0.date) } ?? .never
        completion(Timeline(entries: entries, policy: policy))
    }

    /// One entry per date `WidgetSnapshot.entryDates(from:)` names — that function lives in the
    /// shared file so `WidgetSnapshotTests` can walk it across a day boundary.
    static func entries(for snapshot: WidgetSnapshot, now: Date) -> [WidgetSnapshotEntry] {
        snapshot.entryDates(from: now).map { WidgetSnapshotEntry(date: $0, snapshot: snapshot) }
    }

    private func current() -> WidgetSnapshot {
        guard let suite = WidgetSnapshotStore.appGroupSuite else { return .empty }
        return WidgetSnapshotStore.read(from: suite)
    }

    private static let placeholderSnapshot = WidgetSnapshot(
        routineName: "Push Day A", exerciseCount: 5, streakWeeks: 3,
        trainedDays: [true, true, false, true, true, false, false], updatedAt: .now,
        routineSymbolName: "dumbbell", routineTint: "coral",
        days: [WidgetDayPlan(
            date: Calendar.current.startOfDay(for: .now), routineName: "Push Day A",
            exerciseCount: 5, routineSymbolName: "dumbbell", routineTint: "coral"
        )]
    )
}
