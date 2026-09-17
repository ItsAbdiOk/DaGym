import GymCore
import OSLog
import SwiftUI

/// The Consistency screen (plan.md §6.4): current/longest streak, a GitHub-style 12-month
/// heatmap shaded by sets or minutes, and a Weekly Recap card with week-over-week deltas.
struct ConsistencyView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var grid: [[DayCell?]] = []
    @State private var monthLabels: [Int: String] = [:]
    /// Busiest day's minutes, for the "Time" ramp — found once here rather than by every square.
    @State private var maxMinutes = 0
    @State private var selectedCell: DayCell?
    @State private var shadeBySets = true
    @State private var streak = (current: 0, longest: 0, thisWeekCount: 0)
    @State private var recap: WeeklyRecap?

    private static let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    streakTiles
                    HeatmapCard(
                        grid: grid, monthLabels: monthLabels, maxMinutes: maxMinutes,
                        shadeBySets: $shadeBySets, selectedCell: $selectedCell
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
            .foregroundStyle(DGColor.ink1)
    }

    private var streakTiles: some View {
        DGAdaptiveStack(spacing: DGSpace.s3) {
            StreakTile(title: "Current Streak", value: streak.current, tint: DGColor.prGoldText, gold: true)
            StreakTile(title: "Longest", value: streak.longest, tint: DGColor.ink1, gold: false)
        }
    }

    private func refresh() {
        let state = Self.signposter.beginInterval("ConsistencyView.refresh")
        defer { Self.signposter.endInterval("ConsistencyView.refresh", state) }
        let calendar = preferences.trainingCalendar
        let cells = store.consistencyCells(months: 12, calendar: calendar)
        grid = ConsistencyCalendar.monthGrid(cells: cells, calendar: calendar)
        maxMinutes = cells.map(\.minutes).max() ?? 0
        monthLabels = ConsistencyMonthLabels.labels(for: grid, calendar: calendar)
        streak = Streaks.weekly(
            workoutDates: store.workoutDates(), weeklyGoal: preferences.weeklyGoal, calendar: calendar,
            now: Date()
        )
        recap = store.weeklyRecap(for: Date(), weeklyGoal: preferences.weeklyGoal, calendar: calendar)
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
        .accessibilityElement(children: .combine)
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
struct HeatmapCard: View {
    var grid: [[DayCell?]]
    var monthLabels: [Int: String]
    var maxMinutes: Int
    @Binding var shadeBySets: Bool
    @Binding var selectedCell: DayCell?

    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private static let squareSize: CGFloat = 10
    private static let spacing: CGFloat = 3
    /// As wide as a month name, so a name cut by the scroll edge fades out entirely.
    private static let edgeFade: CGFloat = 34
    private static let labelOverflow: CGFloat = 24
    private static let defaultRamp: [Color] = [
        DGColor.surface3, DGColor.coral.opacity(0.22), DGColor.coral.opacity(0.46),
        DGColor.coral.opacity(0.72), DGColor.coral
    ]

    /// `defaultRamp` unless the system's "Differentiate Without Color" setting or the user's own
    /// `Preferences.colorBlindHeatmaps` toggle asks for `DGColor.consistencyAccessible`.
    private var ramp: [Color] {
        differentiateWithoutColor || preferences.colorBlindHeatmaps
            ? DGColor.consistencyAccessible
            : Self.defaultRamp
    }

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
                // The leading inset sits under `edgeFade` when scrolled fully left, so the first
                // column is never dimmed; the trailing one gives the last month's label (which
                // overflows its 10 pt column) room inside the scrollable content.
                .padding(.leading, Self.edgeFade)
                .padding(.trailing, Self.labelOverflow)
            }
            .defaultScrollAnchor(.trailing) // today is the last column
            // A year is wider than the card, so the view opens scrolled to today with the
            // leading months cut mid-label ("AR" for MAR). Fading that edge reads as "more to
            // the left" rather than a truncated word.
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.edgeFade)
                    Color.black
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
                // Intrinsic size first, then the square-wide slot: the label overflows to the
                // right instead of wrapping one letter per line.
                Text(monthLabels[index] ?? "")
                    .dgLabel()
                    .fixedSize()
                    .frame(width: Self.squareSize, alignment: .leading)
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

    /// A 10 pt square is a precision target by design (a year of days in one card); VoiceOver
    /// gets each trained day as its own button, and the untrained ones are skipped as noise.
    @ViewBuilder
    private func square(for cell: DayCell?) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color(for: cell))
            .frame(width: Self.squareSize, height: Self.squareSize)
            .onTapGesture { if let cell { selectedCell = cell } }
            .accessibilityHidden(cell.map { $0.sets == 0 } ?? true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cell.map(Self.footnote(for:)) ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if let cell { selectedCell = cell } }
    }

    private func color(for cell: DayCell?) -> Color {
        guard let cell else { return .clear }
        let level = shadeBySets ? cell.level : timeLevel(for: cell)
        return ramp[min(4, max(0, level))]
    }

    private func timeLevel(for cell: DayCell) -> Int {
        Self.timeLevel(minutes: cell.minutes, maxMinutes: maxMinutes)
    }

    /// A lightweight local quantile ramp for minutes — mirrors `ConsistencyCalendar`'s sets ramp
    /// but doesn't need its own GymCore entry point since it's purely a display alternative.
    /// `maxMinutes` is the grid's busiest day, computed once by the owner: finding it here made
    /// every one of ~370 squares flatten the whole year on every render.
    static func timeLevel(minutes: Int, maxMinutes: Int) -> Int {
        guard minutes > 0, maxMinutes > 0 else { return 0 }
        let ratio = Double(minutes) / Double(maxMinutes)
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 0.75 { return 3 }
        return 4
    }

    /// "None" and "4+ Sets" bracket the ramp in text, not just colour, whichever ramp is active —
    /// so a colour-blind lifter (or anyone squinting) can still read low vs. high without relying
    /// on hue discrimination.
    private var legend: some View {
        HStack(spacing: DGSpace.s1) {
            Text("None").dgLabel()
            ForEach(Array(ramp.enumerated()), id: \.offset) { _, tint in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: Self.squareSize, height: Self.squareSize)
            }
            Text("4+ Sets").dgLabel()
        }
    }

    private static let footnoteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    static func footnote(for cell: DayCell) -> String {
        "\(footnoteFormatter.string(from: cell.date)) · \(cell.sets) sets · \(cell.minutes) min"
    }
}

/// "WEEKLY RECAP" card: headline numbers with success/danger-tinted week-over-week deltas.
struct WeeklyRecapCard: View {
    var recap: WeeklyRecap
    var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            Text("Weekly Recap").dgLabel()
            DGAdaptiveStack(spacing: DGSpace.s4) {
                metric(
                    value: preferences.formatVolume(kg: recap.volumeKg),
                    unit: "\(preferences.unitSymbol) volume", delta: percentDelta
                )
                metric(value: "\(recap.sets)", unit: "sets", delta: countDelta(recap.setsDelta))
            }
            DGAdaptiveStack(spacing: DGSpace.s4) {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.metricLabel(value: value, unit: unit, delta: delta))
    }

    /// "12 sets, up 3 on last week" — the delta's colour and sign, in words.
    static func metricLabel(value: String, unit: String, delta: (text: String, good: Bool)?) -> String {
        guard let delta else { return "\(value) \(unit)" }
        let amount = delta.text.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        return "\(value) \(unit), \(delta.good ? "up" : "down") \(amount) on last week"
    }
}

#Preview {
    if let store = PreviewStore.make() {
        ConsistencyView()
            .environment(store)
            .environment(Preferences())
    }
}
