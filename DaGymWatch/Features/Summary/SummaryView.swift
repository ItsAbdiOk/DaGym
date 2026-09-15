import GymCore
import SwiftUI

/// Screen 6: "Push A done", three stat cards, the muscles line with the PR count, the 28 × 48 pt
/// body map, Done.
struct SummaryView: View {
    @Environment(WatchStore.self) private var store
    @Environment(WatchPreferences.self) private var preferences

    var body: some View {
        let summary = store.summary
        VStack(spacing: WatchMetric.isSmall ? 6 : 8) {
            SafeBandText(text: title, font: WatchFont.title, color: WatchColor.ink)
            HStack(spacing: 6) {
                statCard("Time", WorkoutSession.clock(summary?.durationSeconds ?? 0))
                statCard("Sets", "\(summary?.setsDone ?? 0)")
                statCard("Volume", volume(summary?.volumeKg ?? 0))
            }
            HStack(spacing: 8) {
                WatchBodyMap(intensity: summary?.musclesHit ?? [:], height: WatchMetric.isSmall ? 40 : 48)
                Text(musclesLine(summary))
                    .font(WatchFont.body)
                    .foregroundStyle(WatchColor.inkSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            CapsuleButton(title: "Done", tint: WatchColor.commit) { store.dismissSummary() }
        }
        .padding(.horizontal, WatchMetric.gutter)
        .padding(.bottom, 2)
        .accessibilityElement(children: .contain)
    }

    /// Names the routine that was done — `summaryTitle` is captured from the session at finish,
    /// so a rest-day pick or a resumed phone workout of another routine reads right.
    private var title: String { "\(store.summaryTitle ?? "Workout") done" }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(WatchFont.secondary)
                .foregroundStyle(WatchColor.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(WatchFont.value(17))
                .foregroundStyle(WatchColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .frame(height: WatchMetric.isSmall ? 44 : 52)
        .background(RoundedRectangle(cornerRadius: WatchMetric.cardRadius).fill(WatchColor.card))
    }

    /// "7.4 t" once a session passes a tonne, "840 kg" below it; lb the same way.
    private func volume(_ kg: Double) -> String {
        let unit = preferences.weightUnit
        let value = unit.display(kg: kg)
        if value >= 1000 { return String(format: "%.1f t", value / 1000) }
        return "\(unit.format(kg: kg, decimals: 0)) \(unit.symbol)"
    }

    private func musclesLine(_ summary: WorkoutSummary?) -> String {
        guard let summary else { return "" }
        let muscles = RoutineMuscles.summary(hitMap: summary.musclesHit)
        let prs = summary.prs.count
        return prs > 0 ? "\(muscles) · \(prs) PR" : muscles
    }
}
