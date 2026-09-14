import Charts
import GymCore
import SwiftUI

/// Scrubbable per-exercise chart — 1RM / Top Set / Volume / Reps — with 3M/6M/1Y/ALL range
/// chips. Shared by `ProgressView` (exercise mode) and `ExerciseDetailView`'s chart card
/// (plan.md §6.4).
struct ExerciseChartView: View {
    var exerciseID: UUID

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var metric = Metric.e1rm
    @State private var range = ChartRange.threeMonths
    @State private var points: [ChartPoint] = []
    @State private var weightOptions: [Double] = []
    @State private var repsWeight: Double = 0
    @State private var scrubbedIndex: Int?
    @State private var neverLoaded = false

    enum Metric: String, CaseIterable, Identifiable {
        case e1rm, topSet, volume, reps
        var id: String { rawValue }
        var title: String {
            switch self {
            case .e1rm: "1RM"
            case .topSet: "Top Set"
            case .volume: "Volume"
            case .reps: "Reps"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            MetricSegmentToggle(metric: $metric)
            if points.count >= 3 {
                headline
                chart
                if metric == .reps, weightOptions.count > 1 {
                    WeightPickerRow(options: weightOptions, selected: $repsWeight)
                }
                if neverLoaded {
                    Text("Never loaded — showing reps per session instead of weight.")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                }
                Text("Drag anywhere on the chart to scrub — the value above updates.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            } else {
                EmptyState(
                    symbol: "chart.line.uptrend.xyaxis",
                    title: "Not Enough History",
                    message: "Charts need three sessions of this exercise. You have \(points.count)."
                )
            }
            RangeChipRow(range: $range)
        }
        .task { refresh() }
        .onChange(of: exerciseID) { _, _ in refresh() }
        .onChange(of: metric) { _, _ in refresh() }
        .onChange(of: range) { _, _ in refresh() }
        .onChange(of: repsWeight) { _, _ in refreshRepsOnly() }
    }

    private var headline: some View {
        let point = displayedPoint
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title).dgLabel()
                Text(point.map(headlineValue) ?? "—")
                    .dgMetric(DGFont.metricL)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer()
            Text(point.map { Self.dateLabel($0.date) } ?? "")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    private var displayedPoint: ChartPoint? {
        if let scrubbedIndex, points.indices.contains(scrubbedIndex) { return points[scrubbedIndex] }
        return points.last
    }

    private func headlineValue(_ point: ChartPoint) -> String {
        switch metric {
        case .e1rm, .topSet, .volume:
            if neverLoaded { return "\(Int(point.value)) reps" }
            return "\(preferences.formatWeight(kg: point.value)) \(preferences.unitSymbol)"
        case .reps:
            return "\(Int(point.value)) reps"
        }
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(x: .value("Session", point.date), y: .value(metric.title, point.value))
                .foregroundStyle(DGColor.coral)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)
            effortDot(point)
            markedPoint(point)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(DGFont.label)
                    .foregroundStyle(DGColor.ink3)
            }
        }
        .frame(height: 160)
        .chartOverlay { proxy in scrubOverlay(proxy: proxy) }
    }

    @ChartContentBuilder
    private func markedPoint(_ point: ChartPoint) -> some ChartContent {
        if isDisplayed(point) {
            if scrubbedIndex != nil {
                RuleMark(x: .value("Session", point.date))
                    .foregroundStyle(DGColor.ink4)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            PointMark(x: .value("Session", point.date), y: .value(metric.title, point.value))
                .foregroundStyle(DGColor.prGold)
                .symbolSize(90)
        }
    }

    /// Top-set line only: a dot per session tinted by the top set's rating, so a flat line of
    /// RPE 10s reads differently from a flat line of RPE 7s. Unrated sessions get no dot.
    @ChartContentBuilder
    private func effortDot(_ point: ChartPoint) -> some ChartContent {
        if metric == .topSet, let rpe = point.rpe, !isDisplayed(point) {
            PointMark(x: .value("Session", point.date), y: .value(metric.title, point.value))
                .foregroundStyle(Effort(rpe: rpe).color)
                .symbolSize(50)
        }
    }

    private func isDisplayed(_ point: ChartPoint) -> Bool {
        guard let displayedPoint else { return false }
        return displayedPoint.date == point.date
    }

    private func scrubOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { updateScrub(at: $0.location, proxy: proxy, geometry: geometry) }
                        .onEnded { _ in scrubbedIndex = nil }
                )
        }
    }

    private func updateScrub(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        guard let date: Date = proxy.value(atX: location.x - origin.x) else { return }
        let nearest = points.indices.min { lhs, rhs in
            abs(points[lhs].date.timeIntervalSince(date)) < abs(points[rhs].date.timeIntervalSince(date))
        }
        guard nearest != scrubbedIndex else { return }
        Haptics.step()
        scrubbedIndex = nearest
    }

    private func refresh() {
        scrubbedIndex = nil
        let bundle = store.exerciseSeries(exerciseID: exerciseID, months: range.months)
        weightOptions = bundle.distinctWeights
        neverLoaded = bundle.neverLoaded
        if repsWeight == 0 || !weightOptions.contains(repsWeight) {
            repsWeight = bundle.mostCommonWeight ?? weightOptions.first ?? 0
        }
        points = points(for: metric, bundle: bundle)
    }

    private func refreshRepsOnly() {
        guard metric == .reps else { return }
        scrubbedIndex = nil
        points = repsPoints()
    }

    private func repsPoints() -> [ChartPoint] {
        let series = store.repsAtWeightSeries(
            exerciseID: exerciseID, months: range.months, weight: repsWeight
        )
        return series.map { ChartPoint(date: $0.date, value: Double($0.value)) }
    }

    private func points(for metric: Metric, bundle: WorkoutStore.ExerciseSeriesBundle) -> [ChartPoint] {
        switch metric {
        case .e1rm where bundle.neverLoaded, .topSet where bundle.neverLoaded:
            return bundle.bestReps.map { ChartPoint(date: $0.date, value: Double($0.value)) }
        case .volume where bundle.neverLoaded:
            return bundle.totalReps.map { ChartPoint(date: $0.date, value: Double($0.value)) }
        case .e1rm:
            return bundle.e1rm.map { ChartPoint(date: $0.date, value: $0.value) }
        case .topSet:
            return bundle.topSet.map {
                ChartPoint(date: $0.date, value: $0.value, rpe: bundle.topSetRPE[$0.date])
            }
        case .volume:
            return bundle.volume.map { ChartPoint(date: $0.date, value: $0.value) }
        case .reps:
            return repsPoints()
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

/// One plotted value, identified by its session date.
private struct ChartPoint: Identifiable {
    var date: Date
    var value: Double
    /// The top set's rating, on the top-set metric only.
    var rpe: Double?
    var id: Date { date }
}

/// 3M / 6M / 1Y / ALL window for a chart.
enum ChartRange: CaseIterable {
    case threeMonths, sixMonths, oneYear, all

    var title: String {
        switch self {
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        case .all: "ALL"
        }
    }

    var months: Int? {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .oneYear: 12
        case .all: nil
        }
    }
}

/// 1RM / Top Set / Volume / Reps segmented toggle, glass pill.
private struct MetricSegmentToggle: View {
    @Binding var metric: ExerciseChartView.Metric

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ExerciseChartView.Metric.allCases) { option in
                let selected = option == metric
                Button {
                    metric = option
                } label: {
                    Text(option.title)
                        .font(DGFont.condensedLabel(12))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(selected ? DGColor.coralText : DGColor.ink3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DGColor.coralWash)
                            }
                        }
                }
                .buttonStyle(.dgControl)
            }
        }
        .dgGlass(.thin, radius: 12)
    }
}

/// 3M/6M/1Y/ALL chip row.
private struct RangeChipRow: View {
    @Binding var range: ChartRange

    var body: some View {
        HStack(spacing: DGSpace.s2) {
            ForEach(ChartRange.allCases, id: \.title) { option in
                DGChip(title: option.title, selected: option == range) { range = option }
            }
        }
    }
}

/// Weight picker for the Reps metric — defaults to the most common weight logged.
private struct WeightPickerRow: View {
    var options: [Double]
    @Binding var selected: Double
    @Environment(Preferences.self) private var preferences

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DGSpace.s2) {
                ForEach(options, id: \.self) { weight in
                    DGChip(title: preferences.formatWeight(kg: weight), selected: weight == selected) {
                        selected = weight
                    }
                }
            }
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        ExerciseChartView(exerciseID: SampleData.bench.id)
            .padding()
            .background(DGColor.bgBase)
            .environment(store)
            .environment(Preferences())
    }
}
