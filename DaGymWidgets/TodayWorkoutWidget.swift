import SwiftUI
import WidgetKit

/// Home Screen widget: today's routine, its exercise count and the current streak. The medium
/// size adds a 7-day dot row of trained days. Reads `WidgetSnapshot` from the App Group — never
/// opens the SwiftData store (see `WidgetSnapshotWriter`).
struct TodayWorkoutWidget: Widget {
    let kind = "TodayWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            TodayWorkoutWidgetView(snapshot: entry.snapshot)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Today's Workout")
        .description("Your scheduled routine, exercise count and streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TodayWorkoutWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
            HStack(spacing: 8) {
                if let symbolName = snapshot.routineSymbolName {
                    RoutineWidgetGlyph(symbolName: symbolName, tint: snapshot.routineTint, size: 26)
                }
                routineName
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(snapshot.exerciseCount)")
                    .font(WidgetFont.condensed(size: 26))
                    .foregroundStyle(WidgetPalette.ink)
                Text(snapshot.exerciseCount == 1 ? "EXERCISE" : "EXERCISES")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetPalette.inkMuted)
                Spacer()
                streakBadge
            }
            if family == .systemMedium {
                dotRow
            }
        }
        .padding(16)
    }

    private var label: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(WidgetPalette.coral).frame(width: 10, height: 10)
            Text("DAGYM · TODAY")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(WidgetPalette.inkMuted)
        }
    }

    private var routineName: some View {
        Text(snapshot.routineName ?? "Rest Day")
            .font(WidgetFont.condensed(size: 22))
            .foregroundStyle(WidgetPalette.ink)
            .lineLimit(2)
    }

    private var streakBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.caption2)
            Text("\(snapshot.streakWeeks)")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(WidgetPalette.coral)
    }

    private var dotRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(snapshot.trainedDays.enumerated()), id: \.offset) { _, trained in
                Circle()
                    .fill(trained ? WidgetPalette.coral : WidgetPalette.ink.opacity(0.15))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
