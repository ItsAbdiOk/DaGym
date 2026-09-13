import GymCore
import SwiftUI

/// The Consistency screen (plan.md §6.4): current/longest streak, a GitHub-style 12-month
/// heatmap shaded by sets or minutes, and a Weekly Recap card with week-over-week deltas.
struct ConsistencyView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var grid: [[DayCell?]] = []
    @State private var monthLabels: [Int: String] = [:]
    @State private var selectedCell: DayCell?
    @State private var shadeBySets = true
    @State private var streak = (current: 0, longest: 0, thisWeekCount: 0)
    @State private var recap: WeeklyRecap?

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    streakTiles
                    HeatmapCard(
                        grid: grid, monthLabels: monthLabels, shadeBySets: $shadeBySets,
                        selectedCell: $selectedCell
                    )
                    if let recap { WeeklyRecapCard(recap: recap, preferences: preferences) }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { refresh() }
    }

    private var header: some View {
        Text("Consistency")
            .font(DGFont.title1)
            .textCase(.uppercase)
            .foregroundStyle(DGColor.ink1)
    }

    private var streakTiles: some View {
        HStack(spacing: DGSpace.s3) {
            StreakTile(title: "Current Streak", value: streak.current, tint: DGColor.prGoldText, gold: true)
            StreakTile(title: "Longest", value: streak.longest, tint: DGColor.ink1, gold: false)
        }
    }

    private func refresh() {
        let calendar = Calendar.current
        let cells = store.consistencyCells(months: 12, calendar: calendar)
        grid = ConsistencyCalendar.monthGrid(cells: cells, calendar: calendar)
        monthLabels = Self.monthLabels(for: grid, calendar: calendar)
        streak = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: preferences.weeklyGoal, calendar: calendar,
            now: Date()
        )
        recap = store.weeklyRecap(for: Date(), weeklyGoal: preferences.weeklyGoal, calendar: calendar)
    }

    /// One label per week-column whose first real day starts a new month.
    private static func monthLabels(for grid: [[DayCell?]], calendar: Calendar) -> [Int: String] {
        var labels: [Int: String] = [:]
        var lastMonth: Int?
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        for (index, week) in grid.enumerated() {
            guard let cell = week.compactMap({ $0 }).first else { continue }
            let month = calendar.component(.month, from: cell.date)
            if month != lastMonth {
                labels[index] = formatter.string(from: cell.date).uppercased()
                lastMonth = month
            }
        }
        return labels
    }
}

/// "Current Streak" (gold-tinted, matches PR chrome) or "Longest" glass tile.
private struct StreakTile: View {
    var title: String
    var value: Int
    var tint: Color
    var gold: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(title).dgLabel(gold ? DGColor.prGoldText : DGColor.ink3)
            HStack(alignment: .firstTextBaseline, spacing: DGSpace.s1) {
                Text("\(value)").dgMetric(DGFont.metricL).foregroundStyle(tint)
                Text(value == 1 ? "week" : "weeks").dgLabel()
            }
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgGlass(.regular, radius: DGRadius.md)
        .overlay {
            if gold {
                RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    .strokeBorder(DGColor.prGold.opacity(0.4), lineWidth: 1)
            }
        }
    }
}

/// The heatmap card: sets/time toggle, month labels, 7-row × N-column grid, ramp legend and a
/// tapped-day footnote.
private struct HeatmapCard: View {
    var grid: [[DayCell?]]
    var monthLabels: [Int: String]
    @Binding var shadeBySets: Bool
    @Binding var selectedCell: DayCell?

    private static let squareSize: CGFloat = 10
    private static let spacing: CGFloat = 3
    private static let ramp: [Color] = [
        DGColor.surface3, DGColor.coral.opacity(0.22), DGColor.coral.opacity(0.46),
        DGColor.coral.opacity(0.72), DGColor.coral
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            HStack {
                Text("12 Months").dgLabel()
                Spacer()
                DGChip(title: "Sets", selected: shadeBySets) { shadeBySets = true }
                DGChip(title: "Time", selected: !shadeBySets) { shadeBySets = false }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DGSpace.s2) {
                    monthHeader
                    heatmapGrid
                }
            }
            legend
            if let selectedCell {
                Text(Self.footnote(for: selectedCell))
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink2)
            }
        }
        .dgCard()
    }

    private var monthHeader: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(grid.indices), id: \.self) { index in
                Text(monthLabels[index] ?? "")
                    .dgLabel()
                    .frame(width: Self.squareSize, alignment: .leading)
                    .fixedSize()
            }
        }
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(Array(grid.indices), id: \.self) { column in
                VStack(spacing: Self.spacing) {
                    ForEach(Array(grid[column].indices), id: \.self) { row in
                        square(for: grid[column][row])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func square(for cell: DayCell?) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color(for: cell))
            .frame(width: Self.squareSize, height: Self.squareSize)
            .onTapGesture { if let cell { selectedCell = cell } }
    }

    private func color(for cell: DayCell?) -> Color {
        guard let cell else { return .clear }
        let level = shadeBySets ? cell.level : timeLevel(for: cell)
        return Self.ramp[min(4, max(0, level))]
    }

    /// A lightweight local quantile ramp for minutes — mirrors `ConsistencyCalendar`'s sets ramp
    /// but doesn't need its own GymCore entry point since it's purely a display alternative.
    private func timeLevel(for cell: DayCell) -> Int {
        let maxMinutes = grid.flatMap { $0.compactMap { $0?.minutes } }.max() ?? 0
        guard cell.minutes > 0, maxMinutes > 0 else { return 0 }
        let ratio = Double(cell.minutes) / Double(maxMinutes)
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 0.75 { return 3 }
        return 4
    }

    private var legend: some View {
        HStack(spacing: DGSpace.s1) {
            Text("None").dgLabel()
            ForEach(Array(Self.ramp.enumerated()), id: \.offset) { _, tint in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: Self.squareSize, height: Self.squareSize)
            }
            Text("4+ Sets").dgLabel()
        }
    }

    private static func footnote(for cell: DayCell) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        let day = formatter.string(from: cell.date)
        return "\(day) · \(cell.sets) sets · \(cell.minutes) min"
    }
}

/// "WEEKLY RECAP" card: headline numbers with success/danger-tinted week-over-week deltas.
private struct WeeklyRecapCard: View {
    var recap: WeeklyRecap
    var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            Text("Weekly Recap").dgLabel()
            HStack(spacing: DGSpace.s4) {
                metric(
                    value: preferences.formatVolume(kg: recap.volumeKg),
                    unit: "\(preferences.unitSymbol) volume", delta: percentDelta
                )
                metric(value: "\(recap.sets)", unit: "sets", delta: countDelta(recap.setsDelta))
            }
            HStack(spacing: DGSpace.s4) {
                metric(
                    value: "\(recap.workouts)", unit: "workouts · goal \(recap.weeklyGoal)", delta: nil
                )
                metric(
                    value: "\(recap.prs)", unit: "personal records", delta: countDelta(recap.prsDelta),
                    gold: true
                )
            }
        }
        .dgCard()
    }

    private var percentDelta: (text: String, good: Bool)? {
        guard let percent = recap.volumeDeltaPercent else { return nil }
        let sign = percent >= 0 ? "+" : ""
        return ("\(sign)\(Int(percent.rounded()))%", percent >= 0)
    }

    private func countDelta(_ delta: Int) -> (text: String, good: Bool)? {
        guard delta != 0 else { return nil }
        let sign = delta > 0 ? "+" : ""
        return ("\(sign)\(delta)", delta > 0)
    }

    private func metric(
        value: String, unit: String, delta: (text: String, good: Bool)?, gold: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DGSpace.s1) {
                Text(value).dgMetric(DGFont.metricM).foregroundStyle(gold ? DGColor.prGoldText : DGColor.ink1)
                if let delta {
                    Text(delta.text)
                        .font(DGFont.caption)
                        .foregroundStyle(delta.good ? DGColor.success : DGColor.danger)
                }
            }
            Text(unit).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        ConsistencyView()
            .environment(store)
            .environment(Preferences())
    }
}
