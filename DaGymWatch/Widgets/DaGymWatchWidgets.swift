import GymCore
import SwiftUI
import WidgetKit

/// Screen 7 complications and 3D Smart Stack card. Three families ship — circular (streak
/// ring), corner (next session), rectangular (resting timer / today's routine) — and while a
/// workout is live the rest timer takes over all of them. "Coach says" is a second widget on
/// the same snapshot: the next planned session plus the on-device coach's one-line tip.
@main
struct DaGymWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DaGymComplication()
        CoachSaysComplication()
    }
}

struct CoachSaysComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "dev.abdirahmanmohamed.dagym.watch.coach", provider: WatchSnapshotProvider()
        ) { entry in
            CoachSaysEntryView(entry: entry)
        }
        .configurationDisplayName("Coach says")
        .description("Your next planned session and the coach's tip.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct CoachSaysEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchSnapshotEntry

    var body: some View {
        CoachSaysView(entry: entry, family: family)
            .containerBackground(.fill.tertiary, for: .widget)
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
/// card on its own; when idle, one at midnight so "Push A today" doesn't outlive the day. The
/// app reloads the timeline whenever it writes a new snapshot, so idle content never asks for
/// a reload of its own — the 30-minute polling this replaced spent the wrist's budget on
/// content that only changes when the app runs.
struct WatchSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchSnapshotEntry {
        var snapshot = WatchSnapshot(streakWeeks: 12, nextRoutineName: "Push A", isNextToday: true)
        snapshot.nextSession = NextPlannedSession(
            routineName: "Push A", dayLabel: "Today", date: .now, exerciseCount: 5, estimatedMinutes: 52
        )
        snapshot.coachLine = "A deload looks due"
        return WatchSnapshotEntry(date: .now, snapshot: snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchSnapshotEntry) -> Void) {
        completion(WatchSnapshotEntry(date: .now, snapshot: current(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchSnapshotEntry>) -> Void) {
        completion(WatchSnapshotEntry.timeline(for: current(at: .now), now: .now))
    }

    /// The App Group snapshot with anything already past dropped — see `WatchSnapshot.expiring`.
    private func current(at now: Date) -> WatchSnapshot {
        (WatchSnapshotStore.appGroupSuite.map(WatchSnapshotStore.read(from:)) ?? .empty).expiring(at: now)
    }
}
