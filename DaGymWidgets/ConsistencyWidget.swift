import GymCore
import SwiftUI
import WidgetKit

/// Home Screen / Lock Screen consistency heatmap (plan.md §6.2): the Progress tab's GitHub-style
/// grid, shaded by counted sets. Medium shows the last 13 weeks, large 26 weeks plus this week's
/// workouts/sets/volume line, and the Lock Screen rectangle this week's seven dots. Same
/// `WidgetSnapshotProvider` as the other widgets, so it re-resolves per midnight entry and is
/// reloaded by the app after every finished workout.
struct ConsistencyWidget: Widget {
    let kind = "ConsistencyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            ConsistencyWidgetView(entry: entry)
        }
        .configurationDisplayName("Consistency")
        .description("Your training heatmap for the last few months.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

private struct ConsistencyWidgetView: View {
    let entry: WidgetSnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetPalette {
        WidgetPalette(
            accent: entry.snapshot.accent, appearance: entry.snapshot.appearance,
            systemIsDark: colorScheme == .dark, colorBlindHeatmaps: entry.snapshot.colorBlindHeatmaps
        )
    }

    private var weeks: Int { family == .systemLarge ? 26 : 13 }

    private var consistency: WidgetConsistency {
        entry.snapshot.consistency(weeks: weeks, on: entry.date)
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            ConsistencyWeekRow(consistency: consistency, weeklyGoal: entry.snapshot.weeklyGoal)
                .containerBackground(.clear, for: .widget)
        default:
            homeScreen
                .padding(16)
                .environment(\.widgetPalette, palette)
                .containerBackground(palette.background, for: .widget)
        }
    }

    @ViewBuilder
    private var homeScreen: some View {
        if entry.day.hasData {
            heatmap
        } else {
            setUpPrompt
        }
    }

    /// Before the first write there is no history to shade — say so, as `TodayWorkoutWidget` does.
    private var setUpPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
            Text("Open DaGym to set up")
                .font(WidgetFont.condensed(size: 20))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            Text("Finish a workout and your heatmap starts here.")
                .font(.caption2)
                .foregroundStyle(palette.inkMuted)
        }
    }

    private var heatmap: some View {
        let consistency = consistency
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                label
                Spacer()
                Text("\(consistency.trainedDays) / \(consistency.totalDays) DAYS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.inkMuted)
            }
            ConsistencyHeatmapGrid(grid: consistency.grid, calendar: entry.snapshot.calendar)
            if family == .systemLarge {
                weekLine(consistency)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(consistency.accessibilityLabel)
    }

    private var label: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(palette.accent).frame(width: 10, height: 10)
            Text("DAGYM · CONSISTENCY")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(palette.inkMuted)
        }
    }

    /// "THIS WEEK  4 workouts · 38 sets · 12 400 kg" — the Weekly Recap's headline, one line.
    private func weekLine(_ consistency: WidgetConsistency) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("THIS WEEK")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(palette.inkMuted)
            Text(Self.weekSummary(consistency, unit: entry.snapshot.weightUnit))
                .font(WidgetFont.condensed(size: 18))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    static func weekSummary(_ consistency: WidgetConsistency, unit: String) -> String {
        let workouts = consistency.thisWeekWorkouts
        var parts = [
            "\(workouts) workout\(workouts == 1 ? "" : "s")",
            "\(consistency.thisWeekSets) sets"
        ]
        if let volumeKg = consistency.weekVolumeKg, volumeKg > 0 {
            let unit = WeightUnit(rawValue: unit) ?? .kg
            let volume = volumeFormatter.string(from: NSNumber(value: unit.display(kg: volumeKg))) ?? "0"
            parts.append("\(volume) \(unit.symbol)")
        }
        return parts.joined(separator: " · ")
    }

    /// `Preferences.formatVolume`'s thin-space grouping, transcribed — the widget can't see it.
    private static let volumeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

/// Lock Screen rectangle: this week's seven days as dots, plus the count against the goal.
private struct ConsistencyWeekRow: View {
    let consistency: WidgetConsistency
    let weeklyGoal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This week")
                .font(.headline)
            HStack(spacing: 6) {
                ForEach(Array(consistency.thisWeek.enumerated()), id: \.offset) { _, trained in
                    Circle()
                        .fill(trained ? Color.primary : Color.clear)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: 1.5))
                        .frame(width: 11, height: 11)
                }
            }
            Text("\(consistency.thisWeekWorkouts) of \(weeklyGoal) workouts")
                .font(.caption2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(consistency.accessibilityLabel)
    }
}

#Preview("Medium", as: .systemMedium) {
    ConsistencyWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, snapshot: .consistencySample)
    WidgetSnapshotEntry(date: .now, snapshot: .consistencySample(colorBlind: true))
}

#Preview("Large", as: .systemLarge) {
    ConsistencyWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, snapshot: .consistencySample)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    ConsistencyWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, snapshot: .consistencySample)
    WidgetSnapshotEntry(date: .now, snapshot: .empty)
}
