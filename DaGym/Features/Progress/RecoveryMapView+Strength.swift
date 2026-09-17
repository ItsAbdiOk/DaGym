import GymCore
import SwiftUI

/// The muscle map's Strength mode: per primary mover, the lifter's top exercises by best
/// estimated 1RM (`WorkoutStore.muscleStrength`, off the PR cache), in the lifter's unit.
struct StrengthMapSection: View {
    var top: [Muscle: [MuscleStrength.Entry]]
    var onSelect: (Muscle) -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            mapCard
            if !top.isEmpty { list }
        }
    }

    private var mapCard: some View {
        VStack(spacing: DGSpace.s4) {
            HStack(spacing: DGSpace.s4) {
                BodyMapView(side: .front, intensity: intensity, onTap: onSelect, regionLabel: regionLabel)
                BodyMapView(side: .back, intensity: intensity, onTap: onSelect, regionLabel: regionLabel)
            }
            .frame(height: 260)
            Text(caption)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dgCard()
    }

    private var intensity: [Muscle: Double] { MuscleStrength.mapIntensity(top) }

    private var caption: String {
        top.isEmpty
            ? "No estimated 1RMs yet — log a loaded set with reps and the map fills in."
            : "Best estimated 1RM per muscle · darker means heavier."
    }

    /// "Chest, best 120 kg on Bench Press".
    private func regionLabel(_ muscle: Muscle, _ value: Double) -> String {
        guard let best = top[muscle]?.first else { return muscle.displayName }
        return "\(muscle.displayName), best \(preferences.formatWeight(kg: best.e1rmKg)) on \(best.name)"
    }

    /// Strongest muscle first, then its top lifts with the number.
    private var list: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Strongest lifts").dgLabel()
            ForEach(ordered, id: \.self) { muscle in
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text(muscle.displayName)
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                    ForEach(top[muscle] ?? []) { entry in
                        HStack {
                            Text(entry.name)
                                .font(DGFont.body)
                                .foregroundStyle(DGColor.ink2)
                                .lineLimit(1)
                            Spacer()
                            Text(preferences.formatWeight(kg: entry.e1rmKg))
                                .dgMetric(DGFont.metricM, tracking: -0.5)
                                .foregroundStyle(DGColor.prGoldText)
                        }
                        .frame(minHeight: 28)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, DGSpace.s1)
            }
        }
        .dgCard()
    }

    private var ordered: [Muscle] {
        Muscle.allCases.filter { top[$0] != nil }.sorted {
            (top[$0]?.first?.e1rmKg ?? 0) > (top[$1]?.first?.e1rmKg ?? 0)
        }
    }
}

/// The three readings of the muscle map.
enum MuscleMapMode: String, CaseIterable, Identifiable {
    case balance, fatigue, strength

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balance: "Balance"
        case .fatigue: "Recovery"
        case .strength: "Strength"
        }
    }

    /// `windowDays` is `WorkoutStore.recoveryWindowDays`, passed in because that constant is
    /// main-actor bound and this enum is not.
    func subtitle(windowDays: Int) -> String {
        switch self {
        case .balance: "Sets per muscle · where the work went"
        case .fatigue: "Fresh → spent · based on the last \(windowDays) days"
        case .strength: "Best estimated 1RM per muscle"
        }
    }
}
