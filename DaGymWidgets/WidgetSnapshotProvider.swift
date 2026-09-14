import WidgetKit

/// Shared `TimelineProvider` for `TodayWorkoutWidget` and `StreakWidget`. Reads the latest
/// `WidgetSnapshot` from the App Group; never touches the SwiftData store. The app calls
/// `WidgetCenter.shared.reloadAllTimelines()` after every write, so a `.never` policy is correct
/// here — there's nothing to recompute on a timer.
struct WidgetSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WidgetSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetSnapshotEntry {
        WidgetSnapshotEntry(date: .now, snapshot: Self.placeholderSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetSnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? Self.placeholderSnapshot : current()
        completion(WidgetSnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetSnapshotEntry>) -> Void) {
        let entry = WidgetSnapshotEntry(date: .now, snapshot: current())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func current() -> WidgetSnapshot {
        guard let suite = WidgetSnapshotStore.appGroupSuite else { return .empty }
        return WidgetSnapshotStore.read(from: suite)
    }

    private static let placeholderSnapshot = WidgetSnapshot(
        routineName: "Push Day A", exerciseCount: 5, streakWeeks: 3,
        trainedDays: [true, true, false, true, true, false, false], updatedAt: .now,
        routineSymbolName: "dumbbell", routineTint: "coral"
    )
}
