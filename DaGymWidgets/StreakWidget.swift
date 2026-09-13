import SwiftUI
import WidgetKit

/// Lock Screen accessory widget (circular + rectangular): current streak in weeks. Same
/// `WidgetSnapshot` source as `TodayWorkoutWidget`.
struct StreakWidget: Widget {
    let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            StreakWidgetView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Your current weekly training streak.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct StreakWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(snapshot.streakWeeks) week\(snapshot.streakWeeks == 1 ? "" : "s")")
                        .font(.headline)
                    Text("Current streak")
                        .font(.caption2)
                }
            }
        default:
            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                Text("\(snapshot.streakWeeks)")
                    .font(WidgetFont.condensed(size: 20))
            }
        }
    }
}
