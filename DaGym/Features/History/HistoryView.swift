import SwiftUI

/// History — workouts grouped by week, with swipe-to-delete, tap-through
/// to detail, and a floating "log a past workout" entry point. Uses a
/// plain `List` (rows styled to look like cards) so swipe actions work.
struct HistoryView: View {
    var records: [WorkoutRecord]
    var workoutsCount: Int
    var volumeKg: Double
    var onBackfill: () -> Void
    var onDelete: (UUID) -> Void

    var body: some View {
        ZStack {
            AmbientWash()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s3)
                list
            }
        }
        .overlay(alignment: .bottom) { backfillButton }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("History")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("\(workoutsCount) workouts · \(Self.thousands(volumeKg)) kg lifted")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        List {
            ForEach(weekGroups, id: \.label) { group in
                Section {
                    ForEach(group.records) { record in row(for: record) }
                } header: {
                    Text(group.label).dgLabel().textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .safeAreaPadding(.bottom, 120)
    }

    private func row(for record: WorkoutRecord) -> some View {
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
        .padding(.bottom, DGSpace.s4)
    }

    /// Records bucketed into "This Week", "Last Week" and, when needed,
    /// month labels for anything older. Week boundaries follow the user's
    /// `Calendar.current.firstWeekday`.
    private var weekGroups: [(label: String, records: [WorkoutRecord])] {
        let calendar = Calendar.current
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

    private static func thousands(_ kg: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: kg)) ?? "\(Int(kg))"
    }
}

/// One workout row: name, day + duration, and a volume/sets/PR footnote.
private struct RecordCard: View {
    var record: WorkoutRecord

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
    }

    private var footnote: String {
        let base = "\(Self.thousands(record.volumeKg)) kg · \(record.sets) sets"
        return record.prCount > 0 ? "\(base) · \(record.prCount) PRs" : base
    }

    private static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private static func thousands(_ kg: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: kg)) ?? "\(Int(kg))"
    }
}

#Preview {
    NavigationStack {
        HistoryView(
            records: SampleData.history, workoutsCount: SampleData.history.count,
            volumeKg: 412_000, onBackfill: {}, onDelete: { _ in }
        )
        .navigationDestination(for: UUID.self) { _ in EmptyView() }
    }
}
