import GymCore
import SwiftUI

/// Workout Summary — "Push A Done". Stat tiles, a PR card, muscles hit,
/// a notes card, and Done/Share actions. Driven entirely by the
/// `WorkoutSummary` the store hands back from `finish(session:)`.
struct WorkoutSummaryView: View {
    var summary: WorkoutSummary
    var title: String
    var onShare: () -> Void
    var onDone: () -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        ZStack {
            AmbientWash(heat: 0.9)
            ScrollView {
                VStack(spacing: DGSpace.s6) {
                    header
                    statRow
                    if !summary.prs.isEmpty { PRCard(prs: summary.prs) }
                    if !summary.achievements.isEmpty {
                        MilestoneUnlockedCard(achievements: summary.achievements)
                    }
                    MusclesHitCard(musclesHit: summary.musclesHit)
                    NotesCard()
                    actionRow
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .task {
            guard !summary.achievements.isEmpty else { return }
            Haptics.personalRecord()
        }
    }

    private var header: some View {
        VStack(spacing: DGSpace.s1) {
            Text("Session complete").dgLabel()
            Text(title)
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
        }
        .frame(maxWidth: .infinity)
    }

    private var statRow: some View {
        HStack(spacing: DGSpace.s3) {
            StatTile(value: WorkoutSession.clock(summary.durationSeconds), label: "Time").dgCard(radius: 14)
            StatTile(value: volumeText, label: "Volume").dgCard(radius: 14)
            StatTile(value: "\(summary.setsDone)", label: "Sets").dgCard(radius: 14)
        }
    }

    /// "7 400 · 5.0 km" once a run is in the session; the plain tonnage otherwise.
    private var volumeText: String {
        let volume = preferences.formatVolume(kg: summary.volumeKg)
        guard summary.distanceMeters > 0 else { return volume }
        return "\(volume) · \(preferences.formatDistance(meters: summary.distanceMeters, decimals: 1))"
    }

    private var actionRow: some View {
        HStack(spacing: DGSpace.s3) {
            DGPrimaryButton(title: "Done", symbol: "checkmark", action: onDone)
                .accessibilityIdentifier(A11yID.summaryDone)
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                    .frame(width: 52, height: 52)
                    .dgGlass(.regular, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
            }
            .buttonStyle(.dgControl)
        }
    }
}

/// Gold-outlined "N personal records" card.
private struct PRCard: View {
    var prs: [PersonalRecordInfo]

    private var titleText: String {
        prs.count == 1 ? "1 Personal Record" : "\(prs.count) Personal Records"
    }

    private var detailText: String {
        prs.map { "\($0.exerciseName) \($0.line)" }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                .fill(DGColor.prGold)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.prGoldText)
                Text(detailText)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DGColor.prGold.opacity(0.10),
            in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.prGold.opacity(0.4), lineWidth: 1)
        }
    }
}

/// Gold "MILESTONE UNLOCKED" card — tasteful, no confetti — listing every tier earned this
/// workout. `AchievementInfo.line` (from `GymCore.Milestones`) already reads well on its own.
private struct MilestoneUnlockedCard: View {
    var achievements: [AchievementInfo]

    private var titleText: String {
        achievements.count == 1 ? "Milestone Unlocked" : "\(achievements.count) Milestones Unlocked"
    }

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s3) {
            RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                .fill(DGColor.prGoldDeep)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                }
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                Text(titleText)
                    .font(DGFont.title3)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.prGoldText)
                ForEach(achievements) { achievement in
                    Text("\(achievement.title) · \(achievement.line)")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DGColor.prGold.opacity(0.10),
            in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.prGold.opacity(0.4), lineWidth: 1)
        }
    }
}

/// Body map + the top three muscles worked, named with their share.
private struct MusclesHitCard: View {
    var musclesHit: [Muscle: Double]

    private var topMuscles: [(muscle: Muscle, share: Double)] {
        let total = musclesHit.values.reduce(0, +)
        guard total > 0 else { return [] }
        return musclesHit.sorted { $0.value > $1.value }.prefix(3)
            .map { (muscle: $0.key, share: $0.value / total) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s4) {
            BodyMapPair(intensity: musclesHit, height: 96)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Muscles Hit").dgLabel()
                if topMuscles.isEmpty {
                    Text("No sets logged")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                } else {
                    // One muscle per line: "Triceps 25%" must never wrap between name and number.
                    ForEach(topMuscles, id: \.muscle) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.muscle.displayName)
                                .font(DGFont.body)
                                .foregroundStyle(DGColor.ink1)
                            Spacer(minLength: DGSpace.s2)
                            Text("\(Int((item.share * 100).rounded()))%")
                                .font(DGFont.title3)
                                .foregroundStyle(DGColor.ink2)
                        }
                    }
                }
            }
        }
        .dgCard()
    }
}

/// Neutral placeholder where the coach debrief will live once Phase 6 lands.
private struct NotesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Notes").dgLabel()
            Text("Debrief arrives with the coach.")
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
    }
}

#Preview {
    WorkoutSummaryView(
        summary: WorkoutSummary(
            durationSeconds: 3124, volumeKg: 6840, setsDone: 18,
            prs: [PersonalRecordInfo(exerciseName: "Bench", line: "82.5 × 8 (e1RM 102.5)")],
            musclesHit: [.chest: 1, .triceps: 0.6, .delts: 0.5],
            achievements: [
                AchievementInfo(
                    milestoneID: "strength.bench", tier: .bronze, title: "Bodyweight Bench",
                    line: "Bronze · e1RM 102 kg with bodyweight 81 kg"
                )
            ]
        ),
        title: "Push A Done", onShare: {}, onDone: {}
    )
    .environment(Preferences())
}
