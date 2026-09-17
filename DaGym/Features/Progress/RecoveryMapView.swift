import GymCore
import SwiftData
import SwiftUI

/// The muscle map in three modes — Balance (sets per muscle over a window), Recovery (the
/// fatigue heatmap, a muscle-by-muscle list, Health context) and Strength (top lifts by e1RM
/// per muscle). Pushed from the You hub and the Progress hub; Home's "See map" opens it as a
/// sheet. Each mode is a hero card (figure on the left, headline and list on the right) with
/// that mode's controls and detail underneath.
struct RecoveryMapView: View {
    /// Which segment the screen opens on: Home wants Recovery, the Progress hub Balance.
    var initialMode = MuscleMapMode.fatigue

    @Environment(WorkoutStore.self) private var store
    // Not `private`: `RecoveryMapView+Health.swift` (kept separate to stay under the
    // type-body-length lint limit) reads these — `private` is file-scoped in Swift, so a
    // same-type extension in a different file can't see a `private` member.
    @Environment(Preferences.self) var preferences
    @Environment(HealthInsightsService.self) var healthInsights
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var snapshot = RecoverySnapshot(map: [:], perMuscle: [], untrainedMuscles: [])
    @State private var selected: MuscleRecovery?
    @State var recoverySignals: HealthInsightsService.RecoverySignals?
    @State var isShowingHealthSettings = false
    @State private var mode: MuscleMapMode
    @State private var horizon = BalanceHorizon.week
    @State private var hardOnly = false
    /// Balance and Strength read the store only once their mode is shown (`.task(id:)`), so
    /// opening the screen costs what it always did.
    @State private var balance: WorkoutStore.BodySeriesBundle?
    @State private var strength: [Muscle: [MuscleStrength.Entry]] = [:]
    /// A question a Balance row handed to the coach; pushing it opens the chat with it written.
    @State private var coachQuestion: String?

    init(initialMode: MuscleMapMode = .fatigue) {
        self.initialMode = initialMode
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s3) {
                    modePicker
                    hero
                    switch mode {
                    case .balance:
                        BalanceMapSection(
                            bundle: balance, snapshot: snapshot, window: $horizon, hardOnly: $hardOnly,
                            onAskCoach: { coachQuestion = $0 }
                        )
                    case .fatigue:
                        healthContextCard
                        RecoveryMuscleList(muscles: snapshot.perMuscle) { selected = $0 }
                    case .strength:
                        StrengthMapSection(top: strength)
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Muscle map")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .task(id: BalanceKey(mode: mode, horizon: horizon, hardOnly: hardOnly)) { loadMode() }
        .sheet(item: $selected) { muscle in
            MuscleDetailSheet(recovery: muscle)
        }
        // Its own destination rather than a `YouDestination`, because Home opens this screen
        // in a sheet with a stack of its own.
        .navigationDestination(isPresented: coachQuestionBinding) {
            CoachChatScreen(launch: coachQuestion.map { .prefilled(question: $0) })
        }
        .sheet(
            isPresented: $isShowingHealthSettings,
            onDismiss: { Task { await refresh() } },
            content: { HealthSettingsView() }
        )
    }

    private var coachQuestionBinding: Binding<Bool> {
        Binding(get: { coachQuestion != nil }, set: { if !$0 { coachQuestion = nil } })
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

    private var modePicker: some View {
        ProgressSegmentControl(
            selection: $mode, title: \.title,
            accessibilityID: { A11yID.recoverySegment($0.title) }, controlLabel: "Map"
        )
        .accessibilityIdentifier(A11yID.recoveryMode)
    }

    @ViewBuilder
    private var hero: some View {
        switch mode {
        case .balance:
            MuscleMapHeroCard(
                model: .balance(bundle: balance, snapshot: snapshot, horizon: horizon, hardOnly: hardOnly),
                onSelect: selectMuscle, onAskCoach: { coachQuestion = $0 }
            )
        case .fatigue:
            MuscleMapHeroCard(model: .recovery(snapshot: snapshot, ramp: ramp), onSelect: selectMuscle)
        case .strength:
            MuscleMapHeroCard(
                model: .strength(top: strength, preferences: preferences), onSelect: selectMuscle
            )
        }
    }

    private var ramp: [Color] {
        DGColor.recoveryRamp(
            differentiateWithoutColor: differentiateWithoutColor,
            colorBlindHeatmaps: preferences.colorBlindHeatmaps
        )
    }

    private func selectMuscle(_ muscle: Muscle) {
        guard let match = snapshot.perMuscle.first(where: { $0.muscle == muscle }) else { return }
        selected = match
    }
}

/// Every trained muscle as a row — name, how much recent work it has taken, when the reading
/// eases off — opening `MuscleDetailSheet`. The hero card shows the top of this list; this is
/// the whole of it.
private struct RecoveryMuscleList: View {
    var muscles: [MuscleRecovery]
    var onSelect: (MuscleRecovery) -> Void

    var body: some View {
        if muscles.isEmpty {
            Text("Log a workout to start tracking recovery.")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
                .padding(.horizontal, DGSpace.s1)
        } else {
            TrainRowGroup {
                ForEach(Array(muscles.enumerated()), id: \.element.id) { offset, muscle in
                    Button { onSelect(muscle) } label: {
                        HStack(spacing: DGSpace.s3) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(muscle.muscle.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(DGColor.ink1)
                                Text(muscle.workloadLabel)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(DGColor.ink3)
                            }
                            Spacer(minLength: 0)
                            Text(muscle.easesOffLabel)
                                .font(.system(size: 12.5))
                                .foregroundStyle(DGColor.ink3)
                                .multilineTextAlignment(.trailing)
                            TrainChevron()
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .trainRowDivider(isLast: offset == muscles.count - 1)
                    }
                    .buttonStyle(.dgRow)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        let store = WorkoutStore(context: container.mainContext)
        let preferences = Preferences()
        NavigationStack { RecoveryMapView() }
            .environment(store)
            .environment(preferences)
            .environment(HealthInsightsService(
                healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
            ))
    } else {
        Text("Preview unavailable")
    }
}
