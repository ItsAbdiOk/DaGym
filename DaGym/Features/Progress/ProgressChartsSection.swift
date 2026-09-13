import Charts
import GymCore
import SwiftUI

/// Body-wide progress summary at the top of the History/Progress tab (plan.md §6.4): this
/// week's headline numbers, 8 weeks of volume and sets-per-muscle over the last 7 days. "See
/// All" opens `ProgressScreen` for the full exercise/body-wide experience. Other agents add
/// their own top-of-tab sections (consistency, milestones) as sibling views — this one only
/// owns its own card stack.
struct ProgressChartsSection: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var bundle: WorkoutStore.BodySeriesBundle?
    @State private var showingProgress = false
    @State private var showingCalculator = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            header
            if let bundle, !bundle.weeklyVolume.isEmpty {
                ThisWeekStrip(thisWeek: bundle.thisWeek, lastWeek: bundle.lastWeek)
                WeeklyVolumeCard(weeks: bundle.weeklyVolume)
                SetsPerMuscleCard(setsPerMuscle: bundle.setsPerMuscle)
            } else {
                EmptyState(
                    symbol: "chart.bar",
                    title: "No Progress Yet",
                    message: "Finish a workout to start seeing charts here."
                )
            }
        }
        .task { refresh() }
        .sheet(isPresented: $showingProgress) {
            ProgressScreen()
        }
        .sheet(isPresented: $showingCalculator) {
            OneRepMaxCalculatorView(bar: preferences.weightUnit.defaultBar)
        }
    }

    private var header: some View {
        HStack {
            Text("Progress").dgLabel()
            Spacer()
            Button("1RM Calculator") { showingCalculator = true }
                .buttonStyle(.plain)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            Button("See All") { showingProgress = true }
                .buttonStyle(.plain)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.coralText)
        }
    }

    private func refresh() {
        var calendar = Calendar.current
        calendar.firstWeekday = preferences.weekStartsMonday ? 2 : 1
        bundle = store.bodySeries(weeks: 8, calendar: calendar)
    }
}

/// Volume / sets / workouts / avg duration, each with a week-over-week delta.
struct ThisWeekStrip: View {
    var thisWeek: WorkoutStore.WeekStats
    var lastWeek: WorkoutStore.WeekStats

    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: 0) {
            DeltaStat(
                value: preferences.formatVolume(kg: thisWeek.volumeKg), label: "Volume",
                delta: percentDelta(thisWeek.volumeKg, lastWeek.volumeKg)
            )
            DeltaStat(
                value: "\(thisWeek.sets)", label: "Sets",
                delta: countDelta(thisWeek.sets, lastWeek.sets)
            )
            DeltaStat(
                value: "\(thisWeek.workouts)", label: "Workouts",
                delta: countDelta(thisWeek.workouts, lastWeek.workouts)
            )
            DeltaStat(
                value: WorkoutSession.clock(thisWeek.avgDurationSeconds), label: "Avg Duration",
                delta: countDelta(thisWeek.avgDurationSeconds, lastWeek.avgDurationSeconds)
            )
        }
        .dgCard(padding: 0)
        .padding(.vertical, DGSpace.s2)
    }

    private func percentDelta(_ current: Double, _ previous: Double) -> String? {
        guard previous > 0 else { return nil }
        let percent = Int(((current - previous) / previous * 100).rounded())
        guard percent != 0 else { return nil }
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }

    private func countDelta(_ current: Int, _ previous: Int) -> String? {
        let delta = current - previous
        guard delta != 0 else { return nil }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }
}

/// One stat with a small success/danger-coloured delta underneath.
private struct DeltaStat: View {
    var value: String
    var label: String
    var delta: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .dgMetric(DGFont.metricM, tracking: -0.5)
                .foregroundStyle(DGColor.ink1)
            Text(label).dgLabel()
            if let delta {
                Text(delta)
                    .font(DGFont.caption)
                    .foregroundStyle(delta.hasPrefix("-") ? DGColor.danger : DGColor.success)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DGSpace.s3)
    }
}

/// 8-week coral bar chart, the most recent week highlighted.
struct WeeklyVolumeCard: View {
    var weeks: [(weekStart: Date, volumeKg: Double)]

    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack {
                Text("Weekly Volume").dgLabel()
                Spacer()
                if let delta { Text(delta).font(DGFont.footnote).foregroundStyle(deltaColor) }
            }
            Chart(Array(weeks.enumerated()), id: \.offset) { index, week in
                BarMark(x: .value("Week", Self.weekLabel(week.weekStart)), y: .value("Volume", week.volumeKg))
                    .foregroundStyle(index == weeks.count - 1 ? DGColor.coral : DGColor.coral.opacity(0.55))
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(DGFont.label).foregroundStyle(DGColor.ink3)
                }
            }
            .frame(height: 120)
        }
        .dgCard()
    }

    private var delta: String? {
        guard weeks.count > 1, let last = weeks.last else { return nil }
        let previous = weeks[weeks.count - 2].volumeKg
        guard previous > 0 else { return nil }
        let percent = Int(((last.volumeKg - previous) / previous * 100).rounded())
        guard percent != 0 else { return nil }
        return (percent > 0 ? "+\(percent)% " : "\(percent)% ") + "vs last week"
    }

    private var deltaColor: Color { (delta ?? "").hasPrefix("-") ? DGColor.danger : DGColor.success }

    private static func weekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "'W'w"
        return formatter.string(from: date)
    }
}

/// Sorted-descending horizontal bars for the top 8 muscles, plus a hit-mode body map pair.
struct SetsPerMuscleCard: View {
    var setsPerMuscle: [Muscle: Double]

    private var topMuscles: [(muscle: Muscle, sets: Double)] {
        setsPerMuscle.sorted { $0.value > $1.value }.prefix(8).map { (muscle: $0.key, sets: $0.value) }
    }

    private var maxSets: Double { topMuscles.map(\.sets).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            Text("Sets Per Muscle · 7 Days").dgLabel()
            if topMuscles.isEmpty {
                Text("No sets logged in the last 7 days.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            } else {
                VStack(spacing: DGSpace.s2) {
                    ForEach(topMuscles, id: \.muscle) { entry in
                        MuscleBarRow(muscle: entry.muscle, sets: entry.sets, maxSets: maxSets)
                    }
                }
                BodyMapPair(mode: .hit, intensity: hitIntensity, height: 120)
                    .frame(maxWidth: .infinity)
            }
        }
        .dgCard()
    }

    private var hitIntensity: [Muscle: Double] {
        guard maxSets > 0 else { return [:] }
        return setsPerMuscle.mapValues { min(1, $0 / maxSets) }
    }
}

/// One "Chest ████ 14" row.
private struct MuscleBarRow: View {
    var muscle: Muscle
    var sets: Double
    var maxSets: Double

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Text(muscle.displayName)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink2)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DGColor.surface3)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(DGColor.coral)
                            .frame(width: geo.size.width * min(1, sets / max(1, maxSets)))
                    }
            }
            .frame(height: 8)
            Text(Self.setsLabel(sets))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private static func setsLabel(_ sets: Double) -> String {
        sets == sets.rounded() ? String(Int(sets)) : String(format: "%.1f", sets)
    }
}
