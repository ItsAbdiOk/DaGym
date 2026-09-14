import SwiftUI

/// History — workouts grouped by week, with swipe-to-delete, tap-through
/// to detail, and a floating "log a past workout" entry point. Uses a
/// plain `List` (rows styled to look like cards) so swipe actions work.
struct HistoryView: View {
    var records: [WorkoutRecord]
    var workoutsCount: Int
    var volumeKg: Double
    /// Total number of cached record lines, for the "RECORDS" tile's subtitle.
    var recordsCount: Int
    /// `Recovery.headline(map:).title`, for the "RECOVERY" tile's subtitle.
    var recoveryHeadline: String
    /// Current weekly streak (`GymCore.Streaks.weekly(...).current`), for the "CONSISTENCY" tile.
    var currentStreakWeeks: Int
    var onBackfill: () -> Void
    var onDelete: (UUID) -> Void
    /// Opens the month calendar sheet (`MonthCalendarSheet`).
    var onCalendar: () -> Void = {}
    /// Body-wide charts rendered above the tiles, scrolling with the list as one page.
    var charts: AnyView = AnyView(EmptyView())

    @Environment(Preferences.self) private var preferences

    var body: some View {
        ZStack {
            AmbientWash()
            list
        }
        .overlay(alignment: .bottom) { backfillButton }
        .dgWarmHaptics()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            charts
            tiles
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text("History").dgLabel()
                    Text(
                        "\(Self.pluralized(workoutsCount, "workout")) · "
                            + "\(preferences.formatVolume(kg: volumeKg)) \(preferences.unitSymbol) lifted"
                    )
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer()
                DGIconButton(
                    symbol: "calendar", size: 36, tint: DGColor.coralText,
                    accessibilityLabel: "Month calendar", action: onCalendar
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Records / Recovery / Consistency / Milestones / Body tiles in a horizontally scrolling
    /// row — five of them never fit a phone width side by side.
    private var tiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DGSpace.s3) {
                tileRow
            }
            .padding(.horizontal, DGSpace.s4)
        }
        .padding(.horizontal, -DGSpace.s4)
        .scrollClipDisabled()
    }

    @ViewBuilder private var tileRow: some View {
            ProgressTile(
                title: "Records", subtitle: Self.pluralized(recordsCount, "record"),
                symbol: "star.fill", tint: DGColor.prGoldText
            ) { PersonalRecordsView() }
            ProgressTile(
                title: "Recovery", subtitle: recoveryHeadline,
                symbol: "figure.stand", tint: DGColor.coralText
            ) { RecoveryMapView() }
            ProgressTile(
                title: "Consistency", subtitle: Self.pluralized(currentStreakWeeks, "week") + " streak",
                symbol: "flame.fill", tint: DGColor.prGoldText
            ) { ConsistencyView() }
            ProgressTile(
                title: "Milestones", subtitle: "Tiers & tonnage",
                symbol: "trophy.fill", tint: DGColor.prGoldText
            ) { MilestonesView() }
            ProgressTile(
                title: "Body", subtitle: "Weight & goal", symbol: "figure", tint: DGColor.infoText
            ) { BodyView() }
    }

    private var list: some View {
        let groups = weekGroups
        let firstLabel = groups.first?.label
        return List {
            header
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s2)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            ForEach(groups, id: \.label) { group in
                Section {
                    ForEach(Array(group.records.enumerated()), id: \.element.id) { offset, record in
                        row(for: record, isFirst: group.label == firstLabel && offset == 0)
                    }
                } header: {
                    Text(group.label).dgLabel().textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaPadding(.bottom, DGSpace.s6)
        .accessibilityIdentifier(A11yID.historyList)
    }

    private func row(for record: WorkoutRecord, isFirst: Bool) -> some View {
        ZStack {
            RecordCard(record: record)
            NavigationLink(value: record.id) { EmptyView() }.opacity(0)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.vertical, DGSpace.s1)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete(record.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier(isFirst ? A11yID.historyRow0 : "")
    }

    private var backfillButton: some View {
        Button(action: onBackfill) {
            HStack(spacing: DGSpace.s2) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 15, weight: .bold))
                Text("Log a Past Workout")
                    .font(DGFont.condensedLabel(14))
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            .foregroundStyle(DGColor.coralText)
            .frame(height: 52)
            .padding(.horizontal, DGSpace.s5)
            .dgGlass(.regular, radius: DGRadius.lg)
        }
        .buttonStyle(DGPressStyle())
        .padding(.bottom, 96) // clear of the floating tab bar
    }

    /// Records bucketed into "This Week", "Last Week" and, when needed,
    /// month labels for anything older. Week boundaries follow
    /// `Preferences.trainingCalendar` (X1/D11/S2) so "This Week" agrees with Home's streak and
    /// the Progress charts.
    private var weekGroups: [(label: String, records: [WorkoutRecord])] {
        let calendar = preferences.trainingCalendar
        let now = Date()
        var buckets: [String: [WorkoutRecord]] = [:]
        var order: [String] = []
        for record in records.sorted(by: { $0.date > $1.date }) {
            let label = Self.weekLabel(for: record.date, now: now, calendar: calendar)
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(record)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private static func weekLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let dateWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let weeksAgo = calendar.dateComponents(
                [.weekOfYear], from: dateWeekStart, to: thisWeekStart
              ).weekOfYear else {
            return "Earlier"
        }
        switch weeksAgo {
        case 0: return "This Week"
        case 1: return "Last Week"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            return formatter.string(from: date).uppercased()
        }
    }

    /// "1 workout" / "2 workouts".
    static func pluralized(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// One workout row: name, day + duration, and a volume/sets/PR footnote.
private struct RecordCard: View {
    var record: WorkoutRecord

    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Spacer()
                Text("\(Self.dayLabel(record.date)) · \(record.durationMinutes) min").dgLabel()
            }
            Text(footnote)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
        .dgCard()
        .accessibilityElement(children: .combine)
    }

    private var footnote: String {
        let volume = "\(preferences.formatVolume(kg: record.volumeKg)) \(preferences.unitSymbol)"
        let base = "\(volume) · \(HistoryView.pluralized(record.sets, "set"))"
        return record.prCount > 0 ? "\(base) · \(record.prCount) PRs" : base
    }

    private static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
}

/// One glass tile in the Progress header row: icon, uppercase label, subtitle.
/// Navigates to `destination` inside the parent's `NavigationStack`.
private struct ProgressTile<Destination: View>: View {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).dgLabel(tint)
                    Text(subtitle)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(DGSpace.s3)
            .frame(width: 184, alignment: .leading)
            .frame(minHeight: DGTap.min)
            .dgGlass(.regular, radius: DGRadius.md)
        }
        .buttonStyle(DGPressStyle())
    }
}

#Preview {
    NavigationStack {
        HistoryView(
            records: SampleData.history, workoutsCount: SampleData.history.count,
            volumeKg: 412_000, recordsCount: 12, recoveryHeadline: "Chest still spent",
            currentStreakWeeks: 3, onBackfill: {}, onDelete: { _ in }
        )
        .navigationDestination(for: UUID.self) { _ in EmptyView() }
    }
    .environment(Preferences())
}
