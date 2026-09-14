import GymCore
import SwiftData
import SwiftUI

/// Full recovery map: front/back body heatmap, a muscle-by-muscle fatigue list, and which
/// muscles saw no training this week. Presented as a sheet from Home's "See Map".
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

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    mapCard
                    healthContextCard
                    muscleList
                    BalanceSection(
                        untrainedMuscles: snapshot.untrainedMuscles,
                        restedMuscles: snapshot.detrainedMuscles
                    )
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { await refresh() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Recovery")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("Fresh → spent · based on the last \(WorkoutStore.recoveryWindowDays) days")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
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
                    .frame(width: 120, alignment: .trailing)
                Image(systemName: "chevron.right")
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

/// What hasn't been trained: the "not this week" tags, plus the graded longest-without-work
/// list the snapshot already computes. Strictly descriptive — how long it has been, never a
/// claim about what that time off has done to the lifter.
private struct BalanceSection: View {
    var untrainedMuscles: [Muscle]
    var restedMuscles: [MuscleRetention]

    /// Enough to be useful, short enough that a lifter two weeks off training doesn't get a
    /// wall of every muscle they own.
    private static let maxListed = 4

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Balance").dgLabel()
            thisWeek
            if !listed.isEmpty { longestWithoutWork }
        }
        .dgCard()
    }

    @ViewBuilder
    private var thisWeek: some View {
        if untrainedMuscles.isEmpty {
            Text("Every muscle group has seen work this week.")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        } else {
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Not trained this week")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
                RecoveryFlowLayout(spacing: DGSpace.s2) {
                    ForEach(untrainedMuscles) { muscle in
                        DGTag(text: muscle.displayName)
                    }
                }
            }
        }
    }

    /// Only muscles this lifter has actually trained at some point: one they have never trained
    /// has nothing to say beyond the "not trained this week" tag it already carries, and a brand
    /// new account would otherwise get a list of four "No sets logged" rows.
    private var listed: [MuscleRetention] {
        Array(restedMuscles.filter { $0.lastTrained != nil }.prefix(Self.maxListed))
    }

    private var longestWithoutWork: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Longest without work")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
            ForEach(listed) { rested in
                HStack {
                    Text(rested.muscle.displayName)
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink2)
                    Spacer()
                    Text(Self.sinceLabel(rested.lastTrained))
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                }
                .frame(height: 28)
            }
        }
    }

    /// "3 weeks ago" / "18 days ago" / "No sets logged" — the fact, not an interpretation of it.
    static func sinceLabel(_ lastTrained: Date?) -> String {
        guard let lastTrained else { return "No sets logged" }
        return lastTrained.formatted(.relative(presentation: .numeric))
    }
}

/// Simple left-to-right, top-to-bottom wrap for the balance tags.
private struct RecoveryFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > width, origin.x > 0 {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            origin.x += size.width + spacing
            maxWidth = max(maxWidth, origin.x)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: origin.y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
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
