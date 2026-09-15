import Charts
import GymCore
import SwiftUI

/// Body-wide effort card (features.md adopt 9): mean rating per week in the lifter's scale with
/// how much of the week was rated, and a hardest-first histogram of every rated set in the
/// window. Callers hide it until `bundle.ratedSets > 0` — a lifter who never rates a set
/// shouldn't see an empty effort chart.
struct EffortCard: View {
    var bundle: WorkoutStore.EffortSeriesBundle

    @Environment(Preferences.self) private var preferences

    private var scale: Effort.Scale { preferences.effortScale }
    private var ratedWeeks: [EffortWeek] { bundle.weeks.filter { $0.ratedSets > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            HStack {
                Text("Effort · \(scale == .rir ? "RIR" : "RPE")").dgLabel()
                Spacer()
                Text(coverageLine)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
            }
            if ratedWeeks.count > 1 {
                weeklyChart
            } else if let week = ratedWeeks.first {
                Text("Averaging \(Self.format(week.meanValue(scale: scale))) \(scaleName) this week.")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            histogram
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }

    private var scaleName: String { scale == .rir ? "RIR" : "RPE" }

    /// "61% of sets rated" across the whole window.
    private var coverageLine: String {
        let rated = bundle.weeks.reduce(0) { $0 + $1.ratedSets }
        let total = bundle.weeks.reduce(0) { $0 + $1.totalSets }
        guard total > 0 else { return "" }
        return "\(Int((Double(rated) / Double(total) * 100).rounded()))% of sets rated"
    }

    private var weeklyChart: some View {
        Chart(ratedWeeks, id: \.weekStart) { week in
            let label = Self.weekLabel(week.weekStart, calendar: preferences.trainingCalendar)
            LineMark(x: .value("Week", label), y: .value("Mean", week.meanValue(scale: scale)))
                .foregroundStyle(DGColor.coral)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Week", label), y: .value("Mean", week.meanValue(scale: scale)))
                .foregroundStyle(Effort(rpe: week.meanRPE).color)
                .symbolSize(60)
                .opacity(0.4 + 0.6 * week.coverage)
        }
        .chartYScale(domain: scale == .rir ? 0...5 : 5...10)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel().font(DGFont.label).foregroundStyle(DGColor.ink3)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(DGFont.label).foregroundStyle(DGColor.ink3)
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Mean \(scaleName) per week")
    }

    private var histogram: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Hardest First").dgLabel()
            let maxCount = max(1, bundle.histogram.map(\.count).max() ?? 1)
            ForEach(bundle.histogram, id: \.effort) { bin in
                HStack(spacing: DGSpace.s3) {
                    Text("\(scaleName) \(bin.effort.displayValue(scale: scale))")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink2)
                        .frame(minWidth: 56, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(DGColor.surface3)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(bin.effort.color)
                                    .frame(width: geo.size.width * Double(bin.count) / Double(maxCount))
                            }
                    }
                    .frame(height: 8)
                    Text("\(bin.count)")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(scaleName) \(bin.effort.displayValue(scale: scale)): \(bin.count) sets"
                )
            }
        }
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

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
