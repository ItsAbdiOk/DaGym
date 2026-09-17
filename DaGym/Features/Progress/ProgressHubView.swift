import GymCore
import SwiftUI

/// The Progress destination from the You hub: three rings for the week, the top and
/// needs-work muscle tiles, a "Look closer" row group into This week / By exercise / By muscle
/// / Milestones, and the widest coverage gap as a callout whose Fix opens the coach.
struct ProgressHubView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var summary = ProgressHubSummary()

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s3) {
                    ProgressRingsCard(summary: summary)
                    muscleTiles
                    Text("Look closer").dgLabel().padding(.top, 6).padding(.horizontal, DGSpace.s1)
                    lookCloser
                    if let callout = summary.callout {
                        ProgressCallout(callout: callout)
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s4)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .refreshOnStoreChange(refresh)
    }

    private func refresh() {
        summary = ProgressHubSummary.make(store: store, preferences: preferences)
    }

    private var muscleTiles: some View {
        DGAdaptiveStack(spacing: 10) {
            NavigationLink { RecoveryMapView(initialMode: .balance) } label: {
                MuscleTileView(
                    kicker: "Top muscle", tile: summary.topMuscle, empty: "No sets in the last 7 days"
                )
            }
            .buttonStyle(.dgCard)
            NavigationLink { RecoveryMapView(initialMode: .balance) } label: {
                MuscleTileView(
                    kicker: "Needs work", tile: summary.needsWork, empty: "Every muscle has seen work"
                )
            }
            .buttonStyle(.dgCard)
        }
    }

    private var lookCloser: some View {
        TrainRowGroup(radius: 16) {
            ProgressPushRow(
                symbol: "chart.bar.fill", title: "This week", subtitle: "Volume, sets, effort, records"
            ) { ThisWeekView() }
            ProgressPushRow(symbol: "dumbbell.fill", title: "By exercise", subtitle: exerciseSubtitle) {
                ProgressScreen()
            }
            ProgressPushRow(symbol: "figure.stand", title: "By muscle", subtitle: muscleSubtitle) {
                RecoveryMapView(initialMode: .balance)
            }
            ProgressPushRow(
                symbol: "trophy.fill", title: "Milestones", subtitle: "Tiers and tonnage", isLast: true
            ) { MilestonesView() }
        }
    }

    /// "Bench Press 96 kg · Squat 142 kg · 14 tracked", or a nudge when nothing has an e1RM yet.
    private var exerciseSubtitle: String {
        guard summary.trackedExercises > 0 else { return "Log a loaded set to start tracking" }
        let lifts = summary.headlineLifts.map {
            "\($0.name) \(preferences.formatWeight(kg: $0.e1rmKg)) \(preferences.unitSymbol)"
        }
        return (lifts + ["\(summary.trackedExercises) tracked"]).joined(separator: " · ")
    }

    private var muscleSubtitle: String {
        guard summary.musclesOnTarget + summary.musclesBehind > 0 else {
            return "Balance, recovery, strength"
        }
        return "\(summary.musclesOnTarget) on target · \(summary.musclesBehind) behind"
    }
}

/// "TOP MUSCLE / Chest / 18 sets" — one of the two tiles under the rings.
private struct MuscleTileView: View {
    var kicker: String
    var tile: ProgressHubSummary.MuscleTile?
    var empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker).dgLabel()
            Text(tile?.muscle.displayName ?? "—")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(DGColor.ink1)
                .padding(.top, 11)
            Text(tile?.detail ?? empty)
                .font(.system(size: 12.5, weight: tile?.isWarning == true ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(tile?.isWarning == true ? DGColor.prGoldText : DGColor.ink3)
                .lineLimit(2)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
        .accessibilityElement(children: .combine)
    }
}

/// The tinted coverage callout with its accent "Fix" pill. Fix opens the coach with the finding
/// already written as a question ("Biceps have had 4 sets in 14 days. What should I add?"),
/// focused and unsent, so the answer starts from this screen's own words.
private struct ProgressCallout: View {
    var callout: ProgressHubSummary.Callout

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(callout.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                Text(callout.detail)
                    .font(.system(size: 13.5))
                    .foregroundStyle(DGColor.ink2)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            NavigationLink(value: YouDestination.coachQuestion(callout.question)) {
                Text("Fix")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(DGColor.coral, in: Capsule())
            }
            .buttonStyle(DGPressStyle())
            .accessibilityLabel("Fix in Coach")
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 17)
        .background(DGColor.coral.opacity(0.13), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DGColor.coral.opacity(0.3), lineWidth: 0.5)
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack { ProgressHubView() }
            .environment(store)
            .environment(Preferences())
    }
}
