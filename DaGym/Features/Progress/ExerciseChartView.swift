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
    /// Every metric's series for the current exercise/range — a metric switch derives from this
    /// instead of fetching the whole bundle again.
    @State private var bundle: WorkoutStore.ExerciseSeriesBundle?
    @State private var points: [ChartPoint] = []
    /// Ticks and labels for `points` — see `ChartAxisPlan` for why the automatic axis is not
    /// used. Held in state because `body` reads it three times per pass, including on every
    /// scrub event, and each evaluation walks the calendar.
    @State private var axisPlan = ChartAxisPlan(granularity: .weeks, ticks: [], labels: [])
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
        .onChange(of: metric) { _, _ in rederive() }
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
        .accessibilityElement(children: .combine)
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
            AxisMarks(values: axisPlan.ticks) { value in
                AxisTick()
                if let date = value.as(Date.self), let index = axisPlan.ticks.firstIndex(of: date) {
                    AxisValueLabel {
                        Text(axisPlan.labels[index]).font(DGFont.label).foregroundStyle(DGColor.ink3)
                    }
                }
            }
        }
        .frame(height: 160)
        .chartOverlay { proxy in scrubOverlay(proxy: proxy) }
        // One adjustable element: the summary as its label, the scrubbed session as its value,
        // and swipe up/down steps through sessions the way a finger drag does.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartSummary)
        .accessibilityValue(displayedPoint.map { "\(headlineValue($0)), \(Self.dateLabel($0.date))" } ?? "")
        .accessibilityAdjustableAction { direction in
            let current = scrubbedIndex ?? (points.isEmpty ? 0 : points.count - 1)
            let next = direction == .increment ? current + 1 : current - 1
            guard points.indices.contains(next) else { return }
            scrubbedIndex = next
        }
    }

    private var chartSummary: String {
        ChartAccessibility.trendSummary(
            title: metric.title, dates: points.map(\.date), values: points.map(\.value),
            format: { value in headlineValue(ChartPoint(id: 0, date: .now, value: value)) }
        )
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
        displayedPoint?.id == point.id
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

    /// Exercise or range changed: one store round trip for the bundle, then derive.
    private func refresh() {
        let bundle = store.exerciseSeries(exerciseID: exerciseID, months: range.months)
        self.bundle = bundle
        weightOptions = bundle.distinctWeights
        neverLoaded = bundle.neverLoaded
        if repsWeight == 0 || !weightOptions.contains(repsWeight) {
            repsWeight = bundle.mostCommonWeight ?? weightOptions.first ?? 0
        }
        rederive()
    }

    /// Metric changed: the bundle already carries every metric, so no fetch (the reps metric is
    /// the exception — its series depends on `repsWeight` and is read on demand).
    private func rederive() {
        guard let bundle else { return }
        setPoints(points(for: metric, bundle: bundle))
    }

    private func refreshRepsOnly() {
        guard metric == .reps else { return }
        setPoints(repsPoints())
    }

    private func setPoints(_ newPoints: [ChartPoint]) {
        scrubbedIndex = nil
        points = newPoints
        axisPlan = Self.axisPlan(for: newPoints)
    }

    private func repsPoints() -> [ChartPoint] {
        let series = store.repsAtWeightSeries(
            exerciseID: exerciseID, months: range.months, weight: repsWeight
        )
        return ChartPoint.series(series.map { (date: $0.date, value: Double($0.value)) })
    }

    private func points(for metric: Metric, bundle: WorkoutStore.ExerciseSeriesBundle) -> [ChartPoint] {
        switch metric {
        case .e1rm where bundle.neverLoaded, .topSet where bundle.neverLoaded:
            return ChartPoint.series(bundle.bestReps.map { (date: $0.date, value: Double($0.value)) })
        case .volume where bundle.neverLoaded:
            return ChartPoint.series(bundle.totalReps.map { (date: $0.date, value: Double($0.value)) })
        case .e1rm:
            return ChartPoint.series(bundle.e1rm)
        case .topSet:
            return ChartPoint.series(bundle.topSet, rpe: bundle.topSetRPE)
        case .volume:
            return ChartPoint.series(bundle.volume)
        case .reps:
            return repsPoints()
        }
    }

    private static func axisPlan(for points: [ChartPoint]) -> ChartAxisPlan {
        guard let first = points.first?.date, let last = points.last?.date else {
            return ChartAxisPlan(granularity: .weeks, ticks: [], labels: [])
        }
        return ChartAxisPlan.plan(from: min(first, last), to: max(first, last))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static func dateLabel(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

/// One plotted value. Identified by its position in the series, not its date: two sessions of
/// the same exercise on one day (a backfill beside a live session) are two points, and a
/// date id would make `Chart` see duplicates and highlight both.
struct ChartPoint: Identifiable, Hashable {
    var id: Int
    var date: Date
    var value: Double
    /// The top set's rating, on the top-set metric only.
    var rpe: Double?

    /// Numbers a series in order, so ids are unique per point and stable between renders.
    /// `rpe` is the top-set metric's rating by session date.
    static func series(_ values: [(date: Date, value: Double)], rpe: [Date: Double] = [:]) -> [ChartPoint] {
        values.enumerated().map { offset, point in
            ChartPoint(id: offset, date: point.date, value: point.value, rpe: rpe[point.date])
        }
    }
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
        DGAdaptiveGrid(columns: 4, spacing: 2) {
            ForEach(ExerciseChartView.Metric.allCases) { option in
                let selected = option == metric
                Button {
                    metric = option
                } label: {
                    Text(option.title)
                        .font(DGFont.condensedLabel(12))
                        .foregroundStyle(selected ? DGColor.coralText : DGColor.ink3)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 32)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DGColor.coralWash)
                            }
                        }
                }
                .buttonStyle(.dgControl)
                .accessibilityAddTraits(selected ? .isSelected : [])
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
