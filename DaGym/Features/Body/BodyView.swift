import SwiftData
import SwiftUI
import UIKit

/// Body — bodyweight trend against an optional goal line, a manual log entry point, an Apple
/// Health pull, the recent-readings list, and progress photos (plan.md §6.4, §6.8).
struct BodyView: View {
    @Environment(WorkoutStore.self) private var store
    // Not `private`: `BodyView+HealthComposition.swift` (kept separate to stay under the
    // type-body-length lint limit) reads these — `private` is file-scoped in Swift, so a
    // same-type extension in a different file can't see a `private` member. Still internal to
    // the module either way.
    @Environment(Preferences.self) var preferences
    @Environment(HealthInsightsService.self) var healthInsights
    @Environment(\.scenePhase) private var scenePhase

    @State private var series: [BodyMeasurementInfo] = []
    @State private var recent: [BodyMeasurementInfo] = []
    @State var composition: HealthInsightsService.BodyComposition?
    @State private var isLoggingWeight = false
    @State private var isEditingGoal = false
    @State private var isSyncing = false
    @State private var isShowingPhotos = false
    @State var isShowingHealthSettings = false
    /// The in-flight `refresh()`; a newer one cancels it so a slow HealthKit answer to an older
    /// save can't land after a newer one.
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    chartCard
                    actionsRow
                    bodyCompositionCard
                    recentList
                    ProgressPhotosCard(onOpen: { isShowingPhotos = true })
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { await refresh() }
        // Every store save bumps `changeToken`; only re-query Health while we're on screen.
        .onChange(of: store.changeToken) { if scenePhase == .active { scheduleRefresh() } }
        .onDisappear { refreshTask?.cancel() }
        .sheet(
            isPresented: $isLoggingWeight,
            onDismiss: scheduleRefresh,
            content: { BodyweightSheet() }
        )
        .sheet(isPresented: $isEditingGoal) { BodyweightSheet(purpose: .goal) }
        .sheet(isPresented: $isShowingPhotos) {
            PhotoLockGate { ProgressPhotosView() }
        }
        .sheet(
            isPresented: $isShowingHealthSettings,
            onDismiss: scheduleRefresh,
            content: { HealthSettingsView() }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Body")
                .font(DGFont.title1)
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
                        .accessibilityElement(children: .combine)
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
                .frame(minHeight: 28)
                .dgGlass(.thin, radius: DGRadius.sm)
        }
        .buttonStyle(.dgControl)
    }

    private var goalLabel: String {
        guard let goalKg = preferences.bodyweightGoalKg else { return "Set Goal" }
        return "Goal \(preferences.formatWeight(kg: goalKg))"
    }

    private var chart: some View {
        TrendChartView(
            points: series.map { TrendChartView.Point(date: $0.date, value: displayWeight($0.kg)) },
            lineColor: DGColor.coral, pointColor: weightPointColor,
            goal: preferences.bodyweightGoalKg.map(displayWeight),
            goalLabel: preferences.bodyweightGoalKg.map { "Goal \(preferences.formatWeight(kg: $0))" },
            title: "Bodyweight",
            formatValue: ChartAccessibility.formatter(unit: preferences.weightUnit.symbol)
        )
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
                    }
                    .foregroundStyle(DGColor.ink1)
                    .frame(minHeight: 52)
                    .padding(.horizontal, DGSpace.s4)
                    .dgGlass(.regular, radius: DGRadius.lg)
                }
                .buttonStyle(.dgControl)
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

    /// Cancels any refresh still waiting on HealthKit and starts a fresh one.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { await refresh() }
    }

    private func refresh() async {
        recent = store.recentBodyMeasurements()
        let merged = await healthInsights.mergedBodyweightSeries()
        guard !Task.isCancelled else { return }
        series = merged
        let latestComposition = await healthInsights.bodyComposition()
        guard !Task.isCancelled else { return }
        composition = latestComposition
    }

    /// "Sync" re-reads Health rather than copying it in: bodyweight held in Health is read live
    /// by `mergedBodyweightSeries` every refresh, because copying it into the main store would
    /// put HealthKit data in iCloud (App Store Guideline 5.1.3).
    private func syncWithHealth() {
        isSyncing = true
        refreshTask?.cancel()
        refreshTask = Task {
            await refresh()
            isSyncing = false
        }
    }

    func displayWeight(_ kg: Double) -> Double { preferences.weightUnit.display(kg: kg) }

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
    private func weightPointColor(_ point: TrendChartView.Point, index: Int) -> Color {
        guard let goalKg = preferences.bodyweightGoalKg, index > 0, index < series.count else {
            return DGColor.coral
        }
        let previous = series[index - 1]
        let current = series[index]
        let movedTowardGoal = abs(current.kg - goalKg) < abs(previous.kg - goalKg)
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
                .frame(minWidth: 64, alignment: .leading)
            Text(preferences.formatWeight(kg: measurement.kg))
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGTag(text: measurement.source == "health" ? "Health" : "Manual")
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: DGTap.min)
        .background(DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static func dateLabel(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

/// "PROGRESS PHOTOS" card — latest thumbnail per pose plus "Add Photo" (plan.md §6.4). Tapping
/// anywhere opens the full `ProgressPhotosView` (behind `PhotoLockGate`, see `BodyView.body`).
/// Thumbnails are decoded once into `thumbnails` so a Body re-render never touches JPEG bytes;
/// the card re-fetches on store saves only while it is on screen in the active scene.
private struct ProgressPhotosCard: View {
    var onOpen: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var latest: [ProgressPhotoInfo] = []
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var isOnScreen = false
    @State private var cardRefreshTask: Task<Void, Never>?

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
        .buttonStyle(.dgCard)
        .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
        .task { await refresh() }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: store.changeToken) {
            guard isOnScreen, scenePhase == .active else { return }
            // One refresh in flight at a time: a delete then an add bump the token twice, and
            // the older fetch finishing last would put the older photos back.
            cardRefreshTask?.cancel()
            cardRefreshTask = Task { await refresh() }
        }
    }

    private func thumbnail(_ photo: ProgressPhotoInfo) -> some View {
        Group {
            if let image = thumbnails[photo.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(DGColor.surface3)
            }
        }
        .frame(width: 64, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.chip, style: .continuous))
    }

    /// Re-fetches the latest photo per pose and decodes only thumbnails not already cached.
    private func refresh() async {
        let fetched = ProgressPhotoPose.allCases.compactMap { store.latestPhoto(pose: $0) }
        var decoded = thumbnails.filter { id, _ in fetched.contains { $0.id == id } }
        for photo in fetched where decoded[photo.id] == nil {
            if let image = await PhotoDecoder.decodeForDisplay(photo.thumbnailData) {
                decoded[photo.id] = image
            }
        }
        guard !Task.isCancelled else { return }
        thumbnails = decoded
        latest = fetched
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
                .environment(HealthInsightsService(
                    healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                ))
        )
    }
    return AnyView(Text("Preview unavailable"))
}
