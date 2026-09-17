import Charts
import GymCore
import SwiftUI

/// "Average effort" card (features.md adopt 9): this week's mean rating in the lifter's scale
/// with an RPE-5…10 histogram of every rated set in the window (tallest bin in the accent),
/// plus the mean-per-week line once more than one week has ratings. Callers hide it until
/// `bundle.ratedSets > 0` — a lifter who never rates a set shouldn't see an empty effort chart.
struct EffortCard: View {
    var bundle: WorkoutStore.EffortSeriesBundle

    @Environment(Preferences.self) private var preferences

    private var scale: Effort.Scale { preferences.effortScale }
    private var ratedWeeks: [EffortWeek] { bundle.weeks.filter { $0.ratedSets > 0 } }
    private var scaleName: String { scale == .rir ? "RIR" : "RPE" }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            ProgressCardTitle(title: "Average effort", trailing: meanLine, trailingTint: DGColor.ink1)
            histogram
            if ratedWeeks.count > 1 {
                weeklyChart
            }
            Text(coverageLine)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
    }

    /// "RPE 7.8" for the latest rated week.
    private var meanLine: String? {
        guard let week = ratedWeeks.last else { return nil }
        return "\(scaleName) \(Self.format(week.meanValue(scale: scale)))"
    }

    /// "61% of sets rated" across the whole window.
    private var coverageLine: String {
        let rated = bundle.weeks.reduce(0) { $0 + $1.ratedSets }
        let total = bundle.weeks.reduce(0) { $0 + $1.totalSets }
        guard total > 0 else { return "" }
        return "\(Int((Double(rated) / Double(total) * 100).rounded()))% of sets rated"
    }

    /// Bins in ascending effort, left to right, so the axis reads 5 … 10 like a scale.
    private var bins: [(effort: Effort, count: Int)] { bundle.histogram.reversed() }

    private var histogram: some View {
        let maxCount = max(1, bins.map(\.count).max() ?? 1)
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(bins, id: \.effort) { bin in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(bin.count == maxCount ? DGColor.coral : DGColor.coral.opacity(0.4))
                        .frame(height: max(8, 56 * Double(bin.count) / Double(maxCount)))
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(binLabel(bin))
                }
            }
            .frame(height: 56, alignment: .bottom)
            HStack(spacing: 5) {
                ForEach(bins, id: \.effort) { bin in
                    Text(bin.effort.displayValue(scale: scale))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DGColor.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func binLabel(_ bin: (effort: Effort, count: Int)) -> String {
        "\(scaleName) \(bin.effort.displayValue(scale: scale)): \(bin.count) sets"
    }

    private var weeklyChart: some View {
        Chart(ratedWeeks, id: \.weekStart) { week in
            let label = Self.weekLabel(week.weekStart, calendar: preferences.trainingCalendar)
            LineMark(x: .value("Week", label), y: .value("Mean", week.meanValue(scale: scale)))
                .foregroundStyle(DGColor.coral)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Week", label), y: .value("Mean", week.meanValue(scale: scale)))
                .foregroundStyle(DGColor.coral)
                .symbolSize(50)
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
        .frame(height: 100)
        .accessibilityLabel("Mean \(scaleName) per week")
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
