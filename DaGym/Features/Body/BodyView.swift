import SwiftData
import SwiftUI
import UIKit

/// Body — the latest reading with its 30-day move and distance to goal over a 12-week line, a
/// manual log entry point and the goal editor, progress photos, the Apple Health composition
/// card and the recent-readings list (plan.md §6.4, §6.8).
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
                VStack(alignment: .leading, spacing: DGSpace.s3) {
                    BodyweightCard(
                        series: series, isSyncing: isSyncing,
                        onLog: { isLoggingWeight = true }, onEditGoal: { isEditingGoal = true },
                        onSync: syncWithHealth
                    )
                    ProgressPhotosCard(onOpen: { isShowingPhotos = true })
                    bodyCompositionCard
                    readingsList
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
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

    /// Recent readings as a white row group — "Today · Manual · 82.4".
    @ViewBuilder
    private var readingsList: some View {
        if recent.isEmpty {
            Text("Nothing logged yet.")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
                .padding(.horizontal, DGSpace.s1)
        } else {
            TrainRowGroup {
                ForEach(Array(recent.enumerated()), id: \.element.id) { offset, reading in
                    MeasurementRow(measurement: reading, isLast: offset == recent.count - 1)
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
}

/// One reading row: "Today / Manual / 82.4".
private struct MeasurementRow: View {
    var measurement: BodyMeasurementInfo
    var isLast: Bool

    @Environment(Preferences.self) private var preferences

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Text(Self.dateLabel(measurement.date))
                .font(.system(size: 15))
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Text(measurement.source == "health" ? "Health" : "Manual")
                .font(.system(size: 13))
                .foregroundStyle(DGColor.ink3)
            Text(preferences.formatWeight(kg: measurement.kg))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DGColor.ink1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .trainRowDivider(isLast: isLast)
        .accessibilityElement(children: .combine)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    /// "Today" / "Monday" inside the last week, "8 Sep" beyond it.
    static func dateLabel(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: now),
           date >= calendar.startOfDay(for: weekAgo) {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return dateFormatter.string(from: date)
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        let store = WorkoutStore(context: container.mainContext)
        let preferences = Preferences()
        return AnyView(
            NavigationStack { BodyView() }
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
