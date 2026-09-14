import Charts
import SwiftUI

/// One line-plus-point trend chart — the bodyweight chart's original treatment on `BodyView`,
/// generalized so any other Health trend (body fat %, lean mass) reuses the same visual
/// language instead of a second chart type. Values are pre-converted by the caller (already in
/// the user's display unit); this view knows nothing about units or goals beyond the optional
/// reference line.
struct TrendChartView: View {
    struct Point: Identifiable {
        var id = UUID()
        var date: Date
        var value: Double
    }

    var points: [Point]
    var lineColor: Color = DGColor.coral
    /// Per-point color, e.g. bodyweight's "moved toward goal" success/danger ramp. Defaults to a
    /// flat `lineColor` for every point.
    var pointColor: (Point, Int) -> Color = { _, _ in DGColor.coral }
    var goal: Double?
    var goalLabel: String?
    var height: CGFloat = 140
    /// What the line is ("Bodyweight", "Body fat") — the VoiceOver summary leads with it.
    var title: String = "Trend"
    /// Renders one value with its unit for the VoiceOver summary ("78.5 kg").
    var formatValue: (Double) -> String = ChartAccessibility.formatter(unit: "")

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(pointColor(point, index))
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(DGColor.info)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        if let goalLabel {
                            Text(goalLabel).dgLabel(DGColor.infoText)
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartYScale(domain: yDomain)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var summary = ChartAccessibility.trendSummary(
            title: title, dates: points.map(\.date), values: points.map(\.value), format: formatValue
        )
        if let goal { summary += ", goal \(formatValue(goal))" }
        return summary
    }

    /// A few units either side of the readings (and the goal) rather than a 0-based axis, so a
    /// small move is visible instead of a flat line at the top of the chart.
    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.value)
        if let goal { values.append(goal) }
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        let pad = max(2, (high - low) * 0.25)
        return (low - pad)...(high + pad)
    }
}
