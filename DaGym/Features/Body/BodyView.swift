import Charts
import SwiftData
import SwiftUI
import UIKit

/// Body — bodyweight trend against an optional goal line, a manual log entry point, an Apple
/// Health pull, the recent-readings list, and progress photos (plan.md §6.4, §6.8).
struct BodyView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(HealthSyncService.self) private var healthSync

    @State private var series: [BodyMeasurementInfo] = []
    @State private var recent: [BodyMeasurementInfo] = []
    @State private var isLoggingWeight = false
    @State private var isEditingGoal = false
    @State private var isSyncing = false
    @State private var isShowingPhotos = false

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    chartCard
                    actionsRow
                    recentList
                    ProgressPhotosCard(onOpen: { isShowingPhotos = true })
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { refresh() }
        .onChange(of: store.changeToken) { refresh() }
        .sheet(isPresented: $isLoggingWeight, onDismiss: refresh) { BodyweightSheet() }
        .sheet(isPresented: $isEditingGoal) { BodyweightSheet(purpose: .goal) }
        .sheet(isPresented: $isShowingPhotos) {
            PhotoLockGate { ProgressPhotosView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Body")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("Bodyweight, trend and Apple Health sync.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bodyweight").dgLabel()
                    if let latest = series.last {
                        HStack(alignment: .firstTextBaseline, spacing: DGSpace.s1) {
                            Text(preferences.formatWeight(kg: latest.kg))
                                .dgMetric(DGFont.metricL)
                                .foregroundStyle(DGColor.ink1)
                            Text(preferences.unitSymbol).dgLabel()
                        }
                    } else {
                        Text("—").dgMetric(DGFont.metricL).foregroundStyle(DGColor.ink3)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: DGSpace.s2) {
                    if let change = changeText { Text(change).dgLabel(changeColor) }
                    goalButton
                }
            }
            if series.isEmpty {
                EmptyState(
                    symbol: "chart.line.uptrend.xyaxis", title: "No Readings Yet",
                    message: "Log your bodyweight to start the trend line."
                )
            } else {
                chart.frame(height: 140)
            }
        }
        .dgCard()
    }

    /// "Goal 80 kg" / "Set Goal" — the only writer of `Preferences.bodyweightGoalKg`.
    private var goalButton: some View {
        Button { isEditingGoal = true } label: {
            Text(goalLabel)
                .dgLabel(DGColor.infoText)
                .padding(.horizontal, DGSpace.s3)
                .frame(height: 28)
                .dgGlass(.thin, radius: DGRadius.sm)
        }
        .buttonStyle(.plain)
    }

    private var goalLabel: String {
        guard let goalKg = preferences.bodyweightGoalKg else { return "Set Goal" }
        return "Goal \(preferences.formatWeight(kg: goalKg))"
    }

    private var chart: some View {
        Chart {
            ForEach(series) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", displayWeight(point.kg)))
                    .foregroundStyle(DGColor.coral)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", point.date), y: .value("Weight", displayWeight(point.kg)))
                    .foregroundStyle(pointColor(for: point))
            }
            if let goalKg = preferences.bodyweightGoalKg {
                RuleMark(y: .value("Goal", displayWeight(goalKg)))
                    .foregroundStyle(DGColor.info)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal \(preferences.formatWeight(kg: goalKg))").dgLabel(DGColor.infoText)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartYScale(domain: yDomain)
    }

    /// A few units either side of the readings (and the goal) rather than a 0-based axis, so a
    /// 75 → 74 kg move is visible instead of a flat line at the top of the chart.
    private var yDomain: ClosedRange<Double> {
        var values = series.map { displayWeight($0.kg) }
        if let goalKg = preferences.bodyweightGoalKg { values.append(displayWeight(goalKg)) }
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        let pad = max(2, (high - low) * 0.25)
        return (low - pad)...(high + pad)
    }

    private var actionsRow: some View {
        HStack(spacing: DGSpace.s3) {
            DGPrimaryButton(title: "Log Bodyweight", symbol: "plus", height: 52) { isLoggingWeight = true }
            if preferences.healthSyncBodyweight {
                Button(action: syncWithHealth) {
                    HStack(spacing: DGSpace.s2) {
                        Image(systemName: "heart.fill").font(.system(size: 14, weight: .semibold))
                        Text(isSyncing ? "Syncing…" : "Sync")
                            .font(DGFont.condensedLabel(13))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(DGColor.ink1)
                    .frame(height: 52)
                    .padding(.horizontal, DGSpace.s4)
                    .dgGlass(.regular, radius: DGRadius.lg)
                }
                .buttonStyle(DGPressStyle())
                .disabled(isSyncing)
            }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Recent Measurements").dgLabel()
            if recent.isEmpty {
                Text("Nothing logged yet.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            } else {
                VStack(spacing: DGSpace.s2) {
                    ForEach(recent) { MeasurementRow(measurement: $0) }
                }
            }
        }
    }

    private func refresh() {
        series = store.bodyweightSeries()
        recent = store.recentBodyMeasurements()
    }

    private func syncWithHealth() {
        isSyncing = true
        Task {
            await healthSync.pullBodyweight()
            refresh()
            isSyncing = false
        }
    }

    private func displayWeight(_ kg: Double) -> Double { preferences.weightUnit.display(kg: kg) }

    private var changeText: String? {
        guard let first = series.first, let last = series.last, first.id != last.id else { return nil }
        let deltaKg = last.kg - first.kg
        let sign = deltaKg > 0 ? "+" : ""
        return "\(sign)\(preferences.formatWeight(kg: deltaKg))"
    }

    private var changeColor: Color {
        guard let goalKg = preferences.bodyweightGoalKg,
              let first = series.first, let last = series.last else {
            return DGColor.ink3
        }
        let movedTowardGoal = abs(last.kg - goalKg) < abs(first.kg - goalKg)
        return movedTowardGoal ? DGColor.success : DGColor.danger
    }

    /// A reading is coloured by whether it moved toward the goal versus the one before it —
    /// success when it did, danger when it moved away, neutral with no goal or no history yet.
    private func pointColor(for point: BodyMeasurementInfo) -> Color {
        guard let goalKg = preferences.bodyweightGoalKg,
              let index = series.firstIndex(where: { $0.id == point.id }), index > 0 else {
            return DGColor.coral
        }
        let previous = series[index - 1]
        let movedTowardGoal = abs(point.kg - goalKg) < abs(previous.kg - goalKg)
        return movedTowardGoal ? DGColor.success : DGColor.danger
    }
}

/// One recent reading row: date, weight, and a Manual/Health source tag.
private struct MeasurementRow: View {
    var measurement: BodyMeasurementInfo

    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Text(Self.dateLabel(measurement.date))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .frame(width: 64, alignment: .leading)
            Text(preferences.formatWeight(kg: measurement.kg))
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGTag(text: measurement.source == "health" ? "Health" : "Manual")
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: DGTap.min)
        .background(DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

/// "PROGRESS PHOTOS" card — latest thumbnail per pose plus "Add Photo" (plan.md §6.4). Tapping
/// anywhere opens the full `ProgressPhotosView` (behind `PhotoLockGate`, see `BodyView.body`).
private struct ProgressPhotosCard: View {
    var onOpen: () -> Void

    @Environment(WorkoutStore.self) private var store
    @State private var latest: [ProgressPhotoInfo] = []

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                HStack {
                    Text("Progress Photos").dgLabel()
                    Spacer()
                    Text("Add Photo").dgLabel(DGColor.coralText)
                }
                if latest.isEmpty {
                    Text("Add a photo to start tracking your progress.")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink3)
                } else {
                    HStack(spacing: DGSpace.s2) { ForEach(latest) { thumbnail($0) } }
                }
            }
            .padding(DGSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(DGPressStyle())
        .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
        .task { refresh() }
    }

    private func thumbnail(_ photo: ProgressPhotoInfo) -> some View {
        Group {
            if let data = photo.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(DGColor.surface3)
            }
        }
        .frame(width: 64, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.chip, style: .continuous))
    }

    private func refresh() {
        latest = ProgressPhotoPose.allCases.compactMap { store.latestPhoto(pose: $0) }
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        let store = WorkoutStore(context: container.mainContext)
        let preferences = Preferences()
        return AnyView(
            BodyView()
                .environment(store)
                .environment(preferences)
                .environment(HealthSyncService(
                    healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                ))
        )
    }
    return AnyView(Text("Preview unavailable"))
}
