import Charts
import GymCore
import SwiftUI

/// The Trends face of "This week": four delta tiles, 8 weeks of volume, sets per muscle over
/// the last 7 days and the effort histogram. Reads its series once per `generation` bump.
struct ProgressChartsSection: View {
    /// Bumped by the owner whenever history changed; the series are re-read on every change.
    var generation = 0
    /// A delta tile was tapped; the owner scrolls or switches segment (`ThisWeekView.jump`).
    var onJump: (TrendsDoor) -> Void = { _ in }

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var bundle: WorkoutStore.BodySeriesBundle?
    @State private var effort: WorkoutStore.EffortSeriesBundle?

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            if let bundle, !bundle.weeklyVolume.isEmpty {
                ThisWeekStrip(thisWeek: bundle.thisWeek, lastWeek: bundle.lastWeek, onJump: onJump)
                WeeklyVolumeCard(weeks: bundle.weeklyVolume)
                    .id(TrendsDoor.volume.anchor)
                SetsPerMuscleCard(setsPerMuscle: bundle.setsPerMuscle)
                    .id(TrendsDoor.sets.anchor)
                // Hidden with effort tracking off, like every other effort surface.
                if preferences.effortTrackingEnabled, let effort, effort.ratedSets > 0 {
                    EffortCard(bundle: effort)
                }
            } else {
                EmptyState(
                    symbol: "chart.bar",
                    title: "No progress yet",
                    message: "Finish a workout to start seeing charts here."
                )
            }
        }
        .task(id: generation) { refresh() }
    }

    private func refresh() {
        bundle = store.bodySeries(weeks: 8, calendar: preferences.trainingCalendar)
        effort = store.effortSeries(weeks: 8, calendar: preferences.trainingCalendar)
    }
}

/// Volume / sets / workouts / avg time, each with a week-over-week delta (accent when up).
struct ThisWeekStrip: View {
    var thisWeek: WorkoutStore.WeekStats
    var lastWeek: WorkoutStore.WeekStats
    var onJump: (TrendsDoor) -> Void = { _ in }

    @Environment(Preferences.self) private var preferences

    var body: some View {
        // Four across normally; a 2×2 grid at accessibility sizes so the numbers keep their font.
        // Every tile is a door: three to the card that explains it, "Avg time" to History,
        // where each session's length is.
        DGAdaptiveGrid(columns: 4, spacing: DGSpace.s2) {
            tile(
                value: "\(preferences.formatVolume(kg: thisWeek.volumeKg)) \(preferences.unitSymbol)",
                label: "Volume", delta: percentDelta(thisWeek.volumeKg, lastWeek.volumeKg),
                hint: "Shows weekly volume"
            ) { onJump(.volume) }
            tile(
                value: "\(thisWeek.sets)", label: "Sets", delta: countDelta(thisWeek.sets, lastWeek.sets),
                hint: "Shows sets per muscle"
            ) { onJump(.sets) }
            tile(
                value: "\(thisWeek.workouts)", label: "Workouts",
                delta: countDelta(thisWeek.workouts, lastWeek.workouts), hint: "Opens Consistency"
            ) { onJump(.workouts) }
            NavigationLink(value: ScreenDestination.history) {
                DeltaStat(
                    value: Self.minutesLabel(thisWeek.avgDurationSeconds), label: "Avg time",
                    delta: minutesDelta(thisWeek.avgDurationSeconds, lastWeek.avgDurationSeconds)
                )
            }
            .buttonStyle(.dgCard)
            .accessibilityHint("Opens History")
            .accessibilityIdentifier(A11yID.trendsTile("Avg time"))
        }
    }

    private func tile(
        value: String, label: String, delta: String?, hint: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DeltaStat(value: value, label: label, delta: delta)
        }
        .buttonStyle(.dgCard)
        .accessibilityHint(hint)
        .accessibilityIdentifier(A11yID.trendsTile(label))
    }

    /// "54m" — the tile is too narrow for a clock.
    static func minutesLabel(_ seconds: Int) -> String { "\(seconds / 60)m" }

    private func percentDelta(_ current: Double, _ previous: Double) -> String? {
        guard previous > 0 else { return nil }
        let percent = (current - previous) / previous * 100
        guard abs(percent) >= 0.05 else { return nil }
        return (percent > 0 ? "+" : "−") + String(format: "%.1f", abs(percent)) + "%"
    }

    /// "+3m" / "−2m" — a duration delta in whole minutes. Nil when there's no previous week to
    /// compare against or nothing moved.
    private func minutesDelta(_ current: Int, _ previous: Int) -> String? {
        guard previous > 0 else { return nil }
        let delta = (current - previous) / 60
        guard delta != 0 else { return nil }
        return (delta > 0 ? "+" : "−") + "\(abs(delta))m"
    }

    private func countDelta(_ current: Int, _ previous: Int) -> String? {
        let delta = current - previous
        guard delta != 0 else { return nil }
        return delta > 0 ? "+\(delta)" : "−\(abs(delta))"
    }
}

/// One stat tile with a small delta underneath — accent when it went up, ink when it went down.
struct DeltaStat: View {
    var value: String
    var label: String
    var delta: String?

    var body: some View {
        ProgressStatTile(
            value: value, label: label, delta: delta, deltaIsPositive: delta?.hasPrefix("+") == true,
            centered: false, reservesDeltaLine: true
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(value: value, label: label, delta: delta))
    }

    /// "Volume, 4 280, up 12 percent on last week" — the sign is otherwise colour plus a glyph.
    /// Accepts both the ASCII hyphen and the typographic minus the tiles print.
    static func accessibilityLabel(value: String, label: String, delta: String?) -> String {
        guard let delta else { return "\(label), \(value)" }
        let direction = delta.hasPrefix("-") || delta.hasPrefix("−") ? "down" : "up"
        let amount = delta.replacingOccurrences(of: "%", with: " percent").dropFirst()
        return "\(label), \(value), \(direction) \(amount) on last week"
    }
}

/// 8-week bar chart, the most recent week in the accent and the rest in a low ink.
struct WeeklyVolumeCard: View {
    var weeks: [(weekStart: Date, volumeKg: Double)]

    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            ProgressCardTitle(
                title: "Weekly volume", trailing: delta,
                trailingTint: delta?.hasPrefix("+") == true ? DGColor.coralText : DGColor.ink3
            )
            if weeks.allSatisfy({ $0.volumeKg == 0 }) {
                Text("Working sets with weight will show up here week by week.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            } else {
                volumeChart
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
    }

    private var volumeChart: some View {
        Chart(Array(weeks.enumerated()), id: \.offset) { index, week in
            let label = Self.weekLabel(week.weekStart, calendar: preferences.trainingCalendar)
            BarMark(x: .value("Week", label), y: .value("Volume", week.volumeKg), width: .ratio(0.78))
                .foregroundStyle(index == weeks.count - 1 ? DGColor.coral : DGColor.ink1.opacity(0.13))
                .cornerRadius(6)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(DGColor.ink3)
            }
        }
        .frame(height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChartAccessibility.periodSummary(
            title: "Weekly volume", periodNoun: "weeks", values: weeks.map(\.volumeKg),
            format: { "\(preferences.formatVolume(kg: $0)) \(preferences.unitSymbol)" }
        ))
    }

    private var delta: String? {
        guard weeks.count > 1, let last = weeks.last else { return nil }
        let previous = weeks[weeks.count - 2].volumeKg
        guard previous > 0 else { return nil }
        let percent = (last.volumeKg - previous) / previous * 100
        guard abs(percent) >= 0.05 else { return nil }
        return (percent > 0 ? "+" : "−") + String(format: "%.1f", abs(percent)) + "% vs last week"
    }

    /// S16: the label must use the same `weekStartsMonday` calendar as the bars themselves
    /// (`WorkoutStore.bodySeries`/`weeklyRecap`), not `DateFormatter`'s implicit
    /// `Calendar.current` — otherwise a locale/preference mismatch can print "W37" under a bar
    /// the data already grouped into week 38.
    private static func weekLabel(_ date: Date, calendar: Calendar) -> String {
        weekFormatter.calendar = calendar
        return weekFormatter.string(from: date)
    }

    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "'W'w"
        return formatter
    }()
}

/// Sorted-descending horizontal bars for the top 8 muscles, accent once a muscle has reached
/// the weekly guide, plus a hit-mode body map pair.
struct SetsPerMuscleCard: View {
    var setsPerMuscle: [Muscle: Double]

    /// Ten counting sets in a week: the bar goes accent from here. A reference line for the
    /// chart, not a prescription — the coach's own floor is the 14-day one in `TrainingConstants`.
    static let weeklyGuideSets = 10.0

    /// Sorted once at construction: `body` used to sort the dictionary three times per pass.
    private let topMuscles: [(muscle: Muscle, sets: Double)]
    private let maxSets: Double
    private let hitIntensity: [Muscle: Double]

    init(setsPerMuscle: [Muscle: Double]) {
        self.setsPerMuscle = setsPerMuscle
        let top = setsPerMuscle.sorted { $0.value > $1.value }.prefix(8)
            .map { (muscle: $0.key, sets: $0.value) }
        let maxSets = top.map(\.sets).max() ?? 1
        topMuscles = top
        self.maxSets = maxSets
        hitIntensity = maxSets > 0 ? setsPerMuscle.mapValues { min(1, $0 / maxSets) } : [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressCardTitle(title: "Sets per muscle · last 7 days")
            if topMuscles.isEmpty {
                Text("No sets logged in the last 7 days.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            } else {
                VStack(spacing: 9) {
                    ForEach(topMuscles, id: \.muscle) { entry in
                        MuscleBarRow(muscle: entry.muscle, sets: entry.sets, maxSets: maxSets)
                    }
                }
                BodyMapPair(mode: .hit, intensity: hitIntensity, height: 120)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
    }
}

/// One "Chest ████ 14 ›" row, opening that muscle's detail on the map.
private struct MuscleBarRow: View {
    var muscle: Muscle
    var sets: Double
    var maxSets: Double

    var body: some View {
        NavigationLink(value: ScreenDestination.muscleDetail(muscle)) {
            HStack(spacing: 10) {
                Text(muscle.displayName)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DGColor.ink3)
                    .frame(width: 76, alignment: .leading)
                    .lineLimit(1)
                GeometryReader { geo in
                    Capsule()
                        .fill(DGColor.ink1.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(fill)
                                .frame(width: geo.size.width * min(1, sets / max(1, maxSets)))
                        }
                }
                .frame(height: 8)
                Text(Self.setsLabel(sets))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                    .frame(minWidth: 24, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(muscle.displayName), \(Self.setsLabel(sets)) sets")
        .accessibilityHint("Opens the muscle map")
    }

    private var fill: Color {
        sets >= SetsPerMuscleCard.weeklyGuideSets ? DGColor.coral : DGColor.ink1.opacity(0.22)
    }

    private static func setsLabel(_ sets: Double) -> String {
        sets == sets.rounded() ? String(Int(sets)) : String(format: "%.1f", sets)
    }
}
