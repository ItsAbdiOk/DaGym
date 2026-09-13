import SwiftUI

/// History — workouts grouped by week, with a floating "log a past workout"
/// entry point.
struct HistoryView: View {
    var records: [WorkoutRecord]
    var onBackfill: () -> Void

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    ForEach(weekGroups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: DGSpace.s3) {
                            Text(group.label).dgLabel()
                            ForEach(group.records) { RecordCard(record: $0) }
                        }
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("History")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("143 workouts · 412 000 kg lifted")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    /// Records bucketed into "This Week", "Last Week" and, when needed,
    /// month labels for anything older.
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
        guard let weeksAgo = calendar.dateComponents([.weekOfYear], from: date, to: now).weekOfYear else {
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
    HistoryView(records: SampleData.history, onBackfill: {})
}
