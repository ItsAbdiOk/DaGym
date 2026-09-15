import SwiftUI
import WidgetKit

/// Screen 7 complications and 3D Smart Stack card. Three families ship — circular (streak
/// ring), corner (next session), rectangular (resting timer / today's routine) — and while a
/// workout is live the rest timer takes over all of them.
@main
struct DaGymWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DaGymComplication()
    }
}

struct DaGymComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "dev.abdirahmanmohamed.dagym.watch", provider: WatchSnapshotProvider()
        ) { entry in
            ComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("DaGym")
        .description("Streak, next session and the rest timer.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

/// Reads the family WidgetKit renders for and hands it to the one shared view.
struct ComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    /// The Smart Stack draws the container background; a face complication does not.
    @Environment(\.showsWidgetContainerBackground) private var inSmartStack
    var entry: WatchSnapshotEntry

    var body: some View {
        ComplicationView(entry: entry, family: family, isSmartStack: inSmartStack)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// One entry now; when resting, another at the rest's end so the timer hands back to the idle
/// card on its own.
struct WatchSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchSnapshotEntry {
        WatchSnapshotEntry(
            date: .now, snapshot: WatchSnapshot(streakWeeks: 12, nextRoutineName: "Push A", isNextToday: true)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchSnapshotEntry) -> Void) {
        completion(WatchSnapshotEntry(date: .now, snapshot: current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchSnapshotEntry>) -> Void) {
        let snapshot = current()
        var entries = [WatchSnapshotEntry(date: .now, snapshot: snapshot)]
        if let rest = snapshot.rest, rest.endDate > .now {
            var idle = snapshot
            idle.rest = nil
            entries.append(WatchSnapshotEntry(date: rest.endDate, snapshot: idle))
        }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func current() -> WatchSnapshot {
        WatchSnapshotStore.appGroupSuite.map(WatchSnapshotStore.read(from:)) ?? .empty
    }
}
