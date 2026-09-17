import GymCore
import SwiftUI

/// History — three lifetime tiles, the month calendar, then workouts grouped by week as white
/// row groups with swipe-to-delete and tap-through to detail. Uses a plain `List` (rows styled
/// into the group recipe) so swipe actions work.
struct HistoryView: View {
    /// Records already bucketed by `HistoryView.weekGroups(records:now:calendar:)` — the
    /// owner does that once per refresh, not on every render.
    var groups: [HistoryWeekGroup]
    var workoutsCount: Int
    var volumeKg: Double
    var thisMonthCount: Int
    var onDelete: (UUID) -> Void
    /// The month calendar card, built by the owner with its callbacks.
    var calendar = AnyView(EmptyView())

    @Environment(Preferences.self) private var preferences

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollViewReader { proxy in
                list(proxy: proxy)
            }
        }
        .dgWarmHaptics()
    }

    private func header(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            tiles(proxy: proxy)
            calendar.id(Self.calendarAnchor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static let calendarAnchor = "history.calendar"
    static let listAnchor = "history.listTop"

    /// Three doors: Workouts scrolls to the list, "kg lifted" opens Records (where the tonnage
    /// came from), This month scrolls to the calendar.
    private func tiles(proxy: ScrollViewProxy) -> some View {
        DGAdaptiveStack(spacing: DGSpace.s2) {
            Button { scroll(to: Self.listAnchor, proxy: proxy) } label: {
                ProgressStatTile(value: "\(workoutsCount)", label: "Workouts")
            }
            .buttonStyle(.dgCard)
            .accessibilityHint("Shows the workout list")
            .accessibilityIdentifier(A11yID.historyTile("Workouts"))
            NavigationLink(value: ScreenDestination.thisWeek(.records)) {
                ProgressStatTile(
                    value: preferences.formatVolume(kg: volumeKg), label: "\(preferences.unitSymbol) lifted"
                )
            }
            .buttonStyle(.dgCard)
            .accessibilityHint("Opens Records")
            .accessibilityIdentifier(A11yID.historyTile("lifted"))
            Button { scroll(to: Self.calendarAnchor, proxy: proxy) } label: {
                ProgressStatTile(value: "\(thisMonthCount)", label: "This month")
            }
            .buttonStyle(.dgCard)
            .accessibilityHint("Shows the calendar")
            .accessibilityIdentifier(A11yID.historyTile("This month"))
        }
    }

    private func scroll(to anchor: String, proxy: ScrollViewProxy) {
        withAnimation(DGMotion.standard) { proxy.scrollTo(anchor, anchor: .top) }
    }

    private func list(proxy: ScrollViewProxy) -> some View {
        let firstLabel = groups.first?.label
        return List {
            header(proxy: proxy)
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if groups.isEmpty {
                EmptyState(
                    symbol: "clock.arrow.circlepath", title: "No workouts yet",
                    message: "Finish a workout, or log a past one with Log."
                )
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s4)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(Array(group.records.enumerated()), id: \.element.id) { offset, record in
                        row(
                            for: record, isFirst: group.label == firstLabel && offset == 0,
                            position: .init(offset: offset, count: group.records.count)
                        )
                    }
                } header: {
                    Text(group.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink3)
                        .padding(.leading, DGSpace.s1)
                        .padding(.top, 6)
                        .padding(.bottom, -1)
                        .id(group.label == firstLabel ? Self.listAnchor : group.label)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaPadding(.bottom, 110)
        .accessibilityIdentifier(A11yID.historyList)
    }

    private func row(for record: WorkoutRecord, isFirst: Bool, position: HistoryRowPosition) -> some View {
        ZStack {
            HistoryRow(record: record, isLast: position.isLast)
            NavigationLink { WorkoutDetailView(workoutID: record.id) } label: { EmptyView() }.opacity(0)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: DGSpace.s4, bottom: 0, trailing: DGSpace.s4))
        .listRowBackground(HistoryRowBackground(position: position).padding(.horizontal, DGSpace.s4))
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete(record.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier(isFirst ? A11yID.historyRow0 : "")
    }

    /// Records bucketed into "This week", "Last week" and, when needed, month labels for
    /// anything older. Week boundaries follow `Preferences.trainingCalendar` (X1/D11/S2) so
    /// "This week" agrees with Home's streak and the Progress charts. Pure and called once per
    /// refresh by `HistoryTabView`, so a sheet dismiss or an undo toast no longer re-sorts and
    /// re-labels every record.
    static func weekGroups(records: [WorkoutRecord], now: Date, calendar: Calendar) -> [HistoryWeekGroup] {
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        var buckets: [String: [WorkoutRecord]] = [:]
        var order: [String] = []
        for record in records.sorted(by: { $0.date > $1.date }) {
            let label = weekLabel(for: record.date, thisWeekStart: thisWeekStart, calendar: calendar)
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(record)
        }
        return order.map { HistoryWeekGroup(label: $0, records: buckets[$0] ?? []) }
    }

    private static func weekLabel(for date: Date, thisWeekStart: Date?, calendar: Calendar) -> String {
        guard let thisWeekStart,
              let dateWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let weeksAgo = calendar.dateComponents(
                [.weekOfYear], from: dateWeekStart, to: thisWeekStart
              ).weekOfYear else {
            return "Earlier"
        }
        switch weeksAgo {
        case 0: return "This Week"
        case 1: return "Last Week"
        default: return monthFormatter.string(from: date).uppercased()
        }
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter
    }()

    /// "1 workout" / "2 workouts".
    static func pluralized(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// One History section — "This Week", "Last Week" or an older month — and its records, newest
/// first. `label` doubles as the identity, as the list's `ForEach` always keyed on it.
struct HistoryWeekGroup: Identifiable, Hashable {
    var label: String
    var records: [WorkoutRecord]
    var id: String { label }
}

/// Where a row sits in its group, so the list can round only the outer corners.
struct HistoryRowPosition {
    var offset: Int
    var count: Int
    var isFirst: Bool { offset == 0 }
    var isLast: Bool { offset == count - 1 }
}

/// The row group's white fill, rounded at the top of the first row and the bottom of the last —
/// a `List` can't wrap a section in one shape, so each row draws its slice of it.
private struct HistoryRowBackground: View {
    var position: HistoryRowPosition
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let radius: CGFloat = 14
        let top: CGFloat = position.isFirst ? radius : 0
        let bottom: CGFloat = position.isLast ? radius : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom,
            topTrailingRadius: top, style: .continuous
        )
        shape
            .fill(Color.white.opacity(scheme == .dark ? 0.07 : 0.72))
            .overlay { shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.9), lineWidth: 0.5) }
    }
}

/// One workout row: title, "Monday · 56 min · 17.1 t · 21 sets", a PR pill when earned.
private struct HistoryRow: View {
    var record: WorkoutRecord
    var isLast: Bool

    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if record.prCount > 0 {
                Text(HistoryView.pluralized(record.prCount, "PR"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DGColor.coralText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DGColor.coralWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            TrainChevron()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .trainRowDivider(isLast: isLast)
        .accessibilityElement(children: .combine)
    }

    /// "Monday · 56 min · 17 100 kg · 21 sets" — `Text(_:format:)` would cache its formatter
    /// too, but the whole line is one string for VoiceOver.
    private var meta: String {
        let day = record.date.formatted(.dateTime.weekday(.wide))
        let volume = "\(preferences.formatVolume(kg: record.volumeKg)) \(preferences.unitSymbol)"
        let sets = HistoryView.pluralized(record.sets, "set")
        return "\(day) · \(record.durationMinutes) min · \(volume) · \(sets)"
    }
}

#Preview {
    NavigationStack {
        HistoryView(
            groups: HistoryView.weekGroups(records: SampleData.history, now: Date(), calendar: .current),
            workoutsCount: SampleData.history.count,
            volumeKg: 412_000, thisMonthCount: 12, onDelete: { _ in }
        )
    }
    .environment(Preferences())
}
