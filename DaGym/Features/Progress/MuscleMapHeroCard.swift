import GymCore
import SwiftUI

/// The muscle map's hero card: the body figure (front and back) on the left, a headline, a
/// sub-sentence and a dotted muscle list on the right. One `Model` per mode so the card is
/// pure presentation — every sentence and dot colour is decided in the model builders below.
struct MuscleMapHeroCard: View {
    struct Row: Identifiable {
        var muscle: Muscle
        var value: String
        var tint: Color
        var id: Muscle { muscle }
    }

    struct Model {
        var headline: String
        var detail: String
        var rows: [Row]
        var mapMode: BodyMapView.Mode
        var intensity: [Muscle: Double]
        /// VoiceOver's name for a region: "Chest, 18 sets".
        var regionLabel: ((Muscle, Double) -> String)?
    }

    var model: Model
    var onSelect: (Muscle) -> Void

    /// Enough rows to read the shape of the week without a wall of every muscle.
    private static let maxRows = 6

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s4) {
            figure
            VStack(alignment: .leading, spacing: 7) {
                Text(model.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DGColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.rows.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(model.rows.prefix(Self.maxRows)) { row in
                            Button { onSelect(row.muscle) } label: { rowView(row) }
                                .buttonStyle(.dgRow)
                        }
                    }
                    .padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dgCard(radius: DGRadius.lg, padding: DGSpace.s4)
    }

    private var figure: some View {
        HStack(spacing: 2) {
            BodyMapView(
                side: .front, mode: model.mapMode, intensity: model.intensity, onTap: onSelect,
                regionLabel: model.regionLabel
            )
            BodyMapView(
                side: .back, mode: model.mapMode, intensity: model.intensity, onTap: onSelect,
                regionLabel: model.regionLabel
            )
        }
        .frame(width: 124, height: 200)
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 9) {
            Circle().fill(row.tint).frame(width: 9, height: 9)
            Text(row.muscle.displayName)
                .font(.system(size: 13))
                .foregroundStyle(DGColor.ink1)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(row.value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DGColor.ink3)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Models

@MainActor
extension MuscleMapHeroCard.Model {
    /// Balance: "Chest is carrying the week", the two least-worked muscles and the longest gap,
    /// then muscles by set count with the dot fading as the count drops.
    static func balance(
        bundle: WorkoutStore.BodySeriesBundle?, snapshot: RecoverySnapshot, horizon: BalanceHorizon,
        hardOnly: Bool
    ) -> Self {
        let sets = (bundle?.setsPerMuscle ?? [:]).filter { $0.value > 0 }
        let sorted = sets.sorted {
            $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value
        }
        let top = sorted.first?.value ?? 0
        let headline: String
        if let leader = sorted.first {
            let verb = leader.key.isPlural ? "are" : "is"
            headline = "\(leader.key.displayName) \(verb) carrying \(horizon.carryingPhrase)"
        } else if hardOnly, bundle?.ratedSetsInWindow == 0 {
            headline = "No sets rated \(horizon.inPhrase)"
        } else {
            headline = "No sets logged \(horizon.inPhrase)"
        }
        var detail = ""
        let trailing = sorted.suffix(2).map(\.key.displayName)
        if sorted.count > 2 {
            let noun = hardOnly ? "hard sets" : "sets"
            detail = "\(trailing.joined(separator: " and ")) have had the fewest \(noun) \(horizon.inPhrase)."
        }
        if let rested = snapshot.detrainedMuscles.first(where: { $0.lastTrained != nil }) {
            let since = BalanceSection.sinceLabel(rested.lastTrained)
            let gap = "Longest without work: \(rested.muscle.displayName), \(since)."
            detail += detail.isEmpty ? gap : " \(gap)"
        }
        if detail.isEmpty, hardOnly, bundle?.ratedSetsInWindow == 0 {
            detail = "Rate RPE as you log, or turn off Hard sets only."
        }
        let intensity = top > 0 ? sets.mapValues { $0 / top } : [:]
        return Self(
            headline: headline, detail: detail,
            rows: sorted.map { entry in
                MuscleMapHeroCard.Row(
                    muscle: entry.key, value: BalanceMapSection.setsLabel(entry.value),
                    tint: DGColor.coral.opacity(0.35 + 0.65 * (top > 0 ? entry.value / top : 0))
                )
            },
            mapMode: .hit, intensity: intensity,
            regionLabel: { muscle, _ in
                "\(muscle.displayName), \(BalanceMapSection.setsLabel(sets[muscle] ?? 0))"
            }
        )
    }

    /// Recovery: the shared `Recovery.headline`, then muscles most-spent first with the dot in
    /// the ramp colour and the row saying when the reading eases off.
    static func recovery(snapshot: RecoverySnapshot, ramp: [Color]) -> Self {
        let headline = Recovery.headline(map: snapshot.map)
        return Self(
            headline: headline.title, detail: headline.body,
            rows: snapshot.perMuscle.map { muscle in
                let step = Int((muscle.spent * Double(ramp.count - 1)).rounded())
                let spent = muscle.spent >= TrainingConstants.coachRecoveryDebtThreshold
                return MuscleMapHeroCard.Row(
                    muscle: muscle.muscle, value: spent ? "Spent" : muscle.easesOffLabel,
                    tint: ramp[min(ramp.count - 1, max(0, step))]
                )
            },
            mapMode: .recovery, intensity: snapshot.map, regionLabel: nil
        )
    }

    /// Strength: the strongest muscle by best e1RM leads, each row its best lift.
    static func strength(top: [Muscle: [MuscleStrength.Entry]], preferences: Preferences) -> Self {
        let ordered = Muscle.allCases.filter { top[$0] != nil }.sorted {
            (top[$0]?.first?.e1rmKg ?? 0) > (top[$1]?.first?.e1rmKg ?? 0)
        }
        let headline: String
        let detail: String
        if let strongest = ordered.first, let best = top[strongest]?.first {
            headline = "\(strongest.displayName) \(strongest.isPlural ? "lead" : "leads") on estimated 1RM"
            let weight = "\(preferences.formatWeight(kg: best.e1rmKg)) \(preferences.unitSymbol)"
            detail = "\(best.name) at \(weight). Darker means heavier."
        } else {
            headline = "No estimated 1RMs yet"
            detail = "Log a loaded set with reps and the map fills in."
        }
        let intensity = MuscleStrength.mapIntensity(top)
        return Self(
            headline: headline, detail: detail,
            rows: ordered.compactMap { muscle in
                guard let best = top[muscle]?.first else { return nil }
                return MuscleMapHeroCard.Row(
                    muscle: muscle,
                    value: "\(preferences.formatWeight(kg: best.e1rmKg)) \(preferences.unitSymbol)",
                    tint: DGColor.coral.opacity(0.35 + 0.65 * (intensity[muscle] ?? 0))
                )
            },
            mapMode: .hit, intensity: intensity,
            regionLabel: { muscle, _ in
                guard let best = top[muscle]?.first else { return muscle.displayName }
                let weight = preferences.formatWeight(kg: best.e1rmKg)
                return "\(muscle.displayName), best \(weight) on \(best.name)"
            }
        )
    }
}
