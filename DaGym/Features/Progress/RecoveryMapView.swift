import GymCore
import SwiftData
import SwiftUI

/// The muscle map in three modes — Balance (sets per muscle over a window), Fatigue (the
/// recovery heatmap, a muscle-by-muscle fatigue list, Health context) and Strength (top lifts
/// by e1RM per muscle). Presented as a sheet from Home's "See Map"; opens on Fatigue.
struct RecoveryMapView: View {
    @Environment(WorkoutStore.self) private var store
    // Not `private`: `RecoveryMapView+Health.swift` (kept separate to stay under the
    // type-body-length lint limit) reads these — `private` is file-scoped in Swift, so a
    // same-type extension in a different file can't see a `private` member.
    @Environment(Preferences.self) var preferences
    @Environment(HealthInsightsService.self) var healthInsights
    @State private var snapshot = RecoverySnapshot(map: [:], perMuscle: [], untrainedMuscles: [])
    @State private var selected: MuscleRecovery?
    @State var recoverySignals: HealthInsightsService.RecoverySignals?
    @State var isShowingHealthSettings = false
    @State private var mode = MuscleMapMode.fatigue
    @State private var horizon = BalanceHorizon.week
    @State private var hardOnly = false
    /// Balance and Strength read the store only once their mode is shown (`.task(id:)`), so
    /// opening the sheet costs what it always did.
    @State private var balance: WorkoutStore.BodySeriesBundle?
    @State private var strength: [Muscle: [MuscleStrength.Entry]] = [:]

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    modePicker
                    switch mode {
                    case .balance:
                        BalanceMapSection(
                            bundle: balance, snapshot: snapshot, window: $horizon, hardOnly: $hardOnly,
                            onSelect: selectMuscle
                        )
                    case .fatigue:
                        mapCard
                        healthContextCard
                        muscleList
                    case .strength:
                        StrengthMapSection(top: strength, onSelect: selectMuscle)
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { await refresh() }
        .task(id: BalanceKey(mode: mode, horizon: horizon, hardOnly: hardOnly)) { loadMode() }
        .sheet(item: $selected) { muscle in
            MuscleDetailSheet(recovery: muscle)
        }
        .sheet(
            isPresented: $isShowingHealthSettings,
            onDismiss: { Task { await refresh() } },
            content: { HealthSettingsView() }
        )
    }

    private func refresh() async {
        // Same calendar Home and the coach use, so the same muscle can't read two ways.
        snapshot = store.recoverySnapshot(calendar: preferences.trainingCalendar)
        recoverySignals = await healthInsights.recoverySignals()
    }

    /// What `.task(id:)` re-runs `loadMode()` for: a mode switch or a Balance control.
    private struct BalanceKey: Equatable {
        var mode: MuscleMapMode
        var horizon: BalanceHorizon
        var hardOnly: Bool
    }

    /// Balance is the coach's `get_muscle_volume` aggregation (`bodySeries`) over the picked
    /// horizon with the training calendar deciding where the week starts; Strength is the PR
    /// cache through the exercise catalogue.
    private func loadMode() {
        switch mode {
        case .balance:
            let calendar = preferences.trainingCalendar
            balance = store.bodySeries(
                weeks: 1, calendar: calendar, balanceWindow: horizon.window(calendar: calendar),
                hardOnly: hardOnly
            )
        case .strength:
            strength = store.muscleStrength()
        case .fatigue:
            break
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text(mode.title)
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text(mode.subtitle(windowDays: WorkoutStore.recoveryWindowDays))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    private var modePicker: some View {
        Picker("Map", selection: $mode) {
            ForEach(MuscleMapMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(A11yID.recoveryMode)
    }

    private var mapCard: some View {
        VStack(spacing: DGSpace.s4) {
            HStack(spacing: DGSpace.s4) {
                BodyMapView(side: .front, mode: .recovery, intensity: snapshot.map, onTap: selectMuscle)
                BodyMapView(side: .back, mode: .recovery, intensity: snapshot.map, onTap: selectMuscle)
            }
            .frame(height: 260)
            RecoveryLegend()
        }
        .dgCard()
    }

    private func selectMuscle(_ muscle: Muscle) {
        guard let match = snapshot.perMuscle.first(where: { $0.muscle == muscle }) else { return }
        selected = match
    }

    private var muscleList: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Muscles").dgLabel()
            if snapshot.perMuscle.isEmpty {
                Text("Log a workout to start tracking recovery.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            } else {
                VStack(spacing: DGSpace.s2) {
                    ForEach(snapshot.perMuscle) { muscle in
                        MuscleListRow(recovery: muscle) { selected = muscle }
                    }
                }
            }
        }
    }
}

/// 5-stop "FRESH … RECOVERING … SPENT" legend row under the map. Text labels sit under the
/// ramp regardless of which ramp is active, so a colour-blind lifter reading the accessible
/// ramp (or anyone glancing quickly) never has to infer status from colour alone.
private struct RecoveryLegend: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            HStack(spacing: 4) {
                ForEach(Array(ramp.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(height: 6)
                }
            }
            HStack {
                Text("Fresh").dgLabel()
                Spacer()
                Text("Recovering").dgLabel()
                Spacer()
                Text("Spent").dgLabel()
            }
        }
    }

    private var ramp: [Color] {
        DGColor.recoveryRamp(
            differentiateWithoutColor: differentiateWithoutColor,
            colorBlindHeatmaps: preferences.colorBlindHeatmaps
        )
    }
}

/// One row: muscle name, a fatigue bar in the ramp colour, and when it'll be fresh again.
private struct MuscleListRow: View {
    var recovery: MuscleRecovery
    var onTap: () -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text(recovery.muscle.displayName)
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(DGColor.surface3)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(rampColor)
                                    .frame(width: geo.size.width * recovery.spent)
                            }
                    }
                    .frame(height: 6)
                }
                Text(statusLabel)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .frame(minWidth: 120, alignment: .trailing)
                Image(systemName: "chevron.right").accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(DGSpace.s4)
            .frame(minHeight: DGTap.min)
            .background(DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    .strokeBorder(DGColor.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.dgRow)
    }

    private var rampColor: Color {
        let index = Int((recovery.spent * 4).rounded())
        let ramp = DGColor.recoveryRamp(
            differentiateWithoutColor: differentiateWithoutColor,
            colorBlindHeatmaps: preferences.colorBlindHeatmaps
        )
        return ramp[min(4, max(0, index))]
    }

    private var statusLabel: String { recovery.easesOffLabel }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        let store = WorkoutStore(context: container.mainContext)
        let preferences = Preferences()
        RecoveryMapView()
            .environment(store)
            .environment(preferences)
            .environment(HealthInsightsService(
                healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
            ))
    } else {
        Text("Preview unavailable")
    }
}
