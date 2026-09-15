import GymCore
import SwiftUI

/// Workout Summary — "Push A Done". Stat tiles, a PR card, muscles hit,
/// a notes card, and Done/Share actions. Driven entirely by the
/// `WorkoutSummary` the store hands back from `finish(session:)`.
struct WorkoutSummaryView: View {
    var summary: WorkoutSummary
    var title: String
    var onDone: () -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                    if let facts = summary.debriefFacts {
                        DebriefCard(facts: facts)
                    }
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
        DGAdaptiveStack(spacing: DGSpace.s3, threshold: .accessibility3) {
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
            shareMenu
        }
    }

    /// Story and square share cards (plan.md §6.4). `Menu` builds its content when it opens, so
    /// the two `ImageRenderer` passes run once per tap, never on every appearance.
    private var shareMenu: some View {
        Menu {
            ShareCardMenuItems(
                model: ShareCardModel(
                    summary: summary, title: title, unit: preferences.weightUnit,
                    distanceUnit: preferences.distanceUnit, calendar: preferences.trainingCalendar
                ),
                preferences: preferences, reduceTransparency: reduceTransparency
            )
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DGColor.ink1)
                .frame(width: 52, height: 52)
                .dgGlass(.regular, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("Share workout")
    }
}

/// One `ShareLink` per card format, both rendered in `init` — i.e. when the menu opens.
private struct ShareCardMenuItems: View {
    private let model: ShareCardModel
    private let images: [(format: WorkoutShareCardFormat, image: WorkoutShareImage)]

    init(model: ShareCardModel, preferences: Preferences, reduceTransparency: Bool) {
        self.model = model
        let stem = model.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        images = WorkoutShareCardFormat.allCases.compactMap { format in
            WorkoutShareCardRenderer.render(
                model, format: format, preferences: preferences, reduceTransparency: reduceTransparency
            ).map {
                (format, WorkoutShareImage(image: $0, filename: "DaGym-\(stem)-\(format.filenameSuffix)"))
            }
        }
    }

    var body: some View {
        ForEach(images, id: \.format) { item in
            ShareLink(
                item: item.image, subject: Text(model.shareSubject), message: Text(model.shareMessage),
                preview: SharePreview(model.shareSubject, image: Image(uiImage: item.image.image))
            ) {
                Label(item.format.menuTitle, systemImage: item.format.symbol)
            }
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
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
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
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
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
        DGAdaptiveStack(verticalAlignment: .top, spacing: DGSpace.s4) {
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
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .dgCard()
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
        title: "Push A Done", onDone: {}
    )
    .environment(Preferences())
    .environment(CoachServices.make(preferences: Preferences()))
}
