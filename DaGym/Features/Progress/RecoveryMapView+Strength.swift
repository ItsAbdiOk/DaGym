import GymCore
import SwiftUI

/// The muscle map's Strength mode, under the hero card: per primary mover, the lifter's top
/// exercises by best estimated 1RM (`WorkoutStore.muscleStrength`, off the PR cache), in the
/// lifter's unit.
struct StrengthMapSection: View {
    var top: [Muscle: [MuscleStrength.Entry]]

    @Environment(Preferences.self) private var preferences

    var body: some View {
        if !top.isEmpty { list }
    }

    /// Strongest muscle first, then its top lifts with the number.
    private var list: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            ProgressCardTitle(title: "Strongest lifts")
            ForEach(ordered, id: \.self) { muscle in
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text(muscle.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                    ForEach(top[muscle] ?? []) { entry in
                        HStack {
                            Text(entry.name)
                                .font(.system(size: 14))
                                .foregroundStyle(DGColor.ink2)
                                .lineLimit(1)
                            Spacer()
                            Text("\(preferences.formatWeight(kg: entry.e1rmKg)) \(preferences.unitSymbol)")
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(DGColor.ink1)
                        }
                        .frame(minHeight: 28)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, DGSpace.s1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
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
