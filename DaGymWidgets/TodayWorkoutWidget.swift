import SwiftUI
import WidgetKit

/// Home Screen widget: today's routine, its exercise count and the current streak. The medium
/// size adds a 7-day dot row of trained days. Reads `WidgetSnapshot` from the App Group — never
/// opens the SwiftData store (see `WidgetSnapshotWriter`) — and re-resolves "today" per timeline
/// entry, so it stays true across midnight with the app closed.
struct TodayWorkoutWidget: Widget {
    let kind = "TodayWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            TodayWorkoutWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Workout")
        .description("Your scheduled routine, exercise count and streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TodayWorkoutWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetPalette {
        WidgetPalette(
            accent: entry.snapshot.accent, appearance: entry.snapshot.appearance,
            systemIsDark: colorScheme == .dark
        )
    }

    var body: some View {
        content
            .padding(16)
            .environment(\.widgetPalette, palette)
            .containerBackground(palette.background, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if entry.day.hasData {
            plannedDay
        } else {
            setUpPrompt
        }
    }

    /// Before the app has ever written a snapshot there is no schedule to report — saying
    /// "Rest Day · 0 EXERCISES" would be a confident lie about an empty store.
    private var setUpPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
            Text("Open DaGym to set up")
                .font(WidgetFont.condensed(size: 20))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text("Pick your routines and we'll show today's here.")
                .font(.caption2)
                .foregroundStyle(palette.inkMuted)
        }
    }

    private var plannedDay: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
            HStack(spacing: 8) {
                if let symbolName = entry.day.routineSymbolName {
                    RoutineWidgetGlyph(symbolName: symbolName, tint: entry.day.routineTint, size: 26)
                }
                routineName
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(entry.day.exerciseCount)")
                    .font(WidgetFont.condensed(size: 26))
                    .foregroundStyle(palette.ink)
                Text(entry.day.exerciseCount == 1 ? "EXERCISE" : "EXERCISES")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.inkMuted)
                Spacer()
                streakBadge
            }
            if family == .systemMedium {
                dotRow
            }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(palette.accent).frame(width: 10, height: 10)
            Text("DAGYM · TODAY")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(palette.inkMuted)
        }
    }

    private var routineName: some View {
        Text(entry.day.routineName ?? "Rest Day")
            .font(WidgetFont.condensed(size: 22))
            .foregroundStyle(palette.ink)
            .lineLimit(2)
    }

    private var streakBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.caption2)
            Text("\(entry.day.streakWeeks)")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(palette.accent)
    }

    private var dotRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(entry.day.trainedDays.enumerated()), id: \.offset) { _, trained in
                Circle()
                    .fill(trained ? palette.accent : palette.ink.opacity(0.15))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
