import GymCore
import SwiftUI

/// Workout Summary from the redesign prototype: the date kicker over a 33 pt title, three stat
/// tiles (Time / Volume / Sets), PRs and milestones, "Muscles hit" with the mini body map, the
/// coach debrief, then "Share card" and an accent "Done". Driven entirely by the
/// `WorkoutSummary` the store hands back from `finish(session:)`.
struct WorkoutSummaryView: View {
    var summary: WorkoutSummary
    var title: String
    var onDone: () -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The summary is shown the moment the workout ends, so its date kicker is simply now.
    @State private var shownAt = Date()
    /// A stat tile's one-line explanation.
    @State private var notice: String?
    /// "Muscles hit" tapped: the muscle map, as a sheet since the summary has no stack.
    @State private var showingMuscleMap = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    var body: some View {
        ZStack {
            AmbientWash(heat: 0.9)
            ScrollView {
                VStack(spacing: 10) {
                    header
                    statRow.padding(.top, 6)
                    if !summary.prs.isEmpty { PRCard(prs: summary.prs) }
                    if !summary.achievements.isEmpty {
                        MilestoneUnlockedCard(achievements: summary.achievements)
                    }
                    Button { showingMuscleMap = true } label: {
                        MusclesHitCard(musclesHit: summary.musclesHit)
                    }
                    .buttonStyle(.dgCard)
                    .accessibilityHint("Opens the muscle map")
                    if let facts = summary.debriefFacts {
                        DebriefCard(facts: facts)
                    }
                    actionRow
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s2)
                .padding(.bottom, 100)
            }
        }
        .background(DGColor.bgBase)
        .dgNoticeToast($notice)
        .sheet(isPresented: $showingMuscleMap) {
            NavigationStack {
                RecoveryMapView(initialMode: .fatigue)
                    .screenDestinations()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingMuscleMap = false }
                        }
                    }
            }
        }
        .task {
            guard !summary.achievements.isEmpty else { return }
            Haptics.personalRecord()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.dateFormatter.string(from: shownAt))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DGColor.ink3)
            Text(title)
                .font(DGFont.title1)
                .foregroundStyle(DGColor.ink1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DGSpace.s1)
        .accessibilityElement(children: .combine)
    }

    private var statRow: some View {
        DGAdaptiveStack(spacing: DGSpace.s2, threshold: .accessibility3) {
            SummaryStatTile(value: WorkoutSession.clock(summary.durationSeconds), label: "Time") {
                notice = WorkoutStatTile.explanation(kicker: "Time")
            }
            SummaryStatTile(value: volumeText, label: "Volume") {
                notice = WorkoutStatTile.explanation(kicker: "Volume")
            }
            SummaryStatTile(value: "\(summary.setsDone)", label: "Sets") {
                notice = "Sets completed in this workout"
            }
        }
    }

    /// "2.2 t" (the header tile's figure), with "· 5.0 km" once a run is in the session.
    private var volumeText: String {
        let tile = ActiveWorkoutView.volumeTile(kg: summary.volumeKg, preferences: preferences)
        let volume = "\(tile.value) \(tile.suffix)"
        guard summary.distanceMeters > 0 else { return volume }
        return "\(volume) · \(preferences.formatDistance(meters: summary.distanceMeters, decimals: 1))"
    }

    private var actionRow: some View {
        DGAdaptiveStack(spacing: DGSpace.s2) {
            shareMenu
            Button(action: onDone) {
                Text("Done")
                    .font(DGFont.condensedLabel(13.5))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        DGColor.coral, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    )
            }
            .buttonStyle(.dgControl)
            .accessibilityIdentifier(A11yID.summaryDone)
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
            Text("Share card")
                .font(DGFont.condensedLabel(13.5))
                .foregroundStyle(DGColor.ink1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .dgTile(radius: DGRadius.md, opacity: 0.66)
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

/// A 20 pt bold value over an 11 pt label, centred, on a flat tile. The workout is not in
/// History until Done, so a tap explains the number rather than going somewhere.
private struct SummaryStatTile: View {
    var value: String
    var label: String
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DGColor.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DGSpace.s3)
            .padding(.vertical, 14)
            .dgTile(radius: 18, opacity: 0.66)
        }
        .buttonStyle(.dgCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value), \(label)")
        .accessibilityHint("Explains this number")
    }
}

/// "N personal records", star on an accent disc.
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
            Circle()
                .fill(DGColor.coral)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                Text(detailText)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DGSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgTile(radius: 20, opacity: 0.66)
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
            Circle()
                .fill(DGColor.coral)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DGColor.inkOnCoral)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                Text(titleText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
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
        .dgTile(radius: 20, opacity: 0.66)
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

    /// "Chest 46% · Shoulders 31% · Triceps 23%" — one line, as the prototype prints it.
    private var line: String {
        guard !topMuscles.isEmpty else { return "No sets logged" }
        return topMuscles
            .map { "\($0.muscle.displayName) \(Int(($0.share * 100).rounded()))%" }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            BodyMapPair(intensity: musclesHit, height: 76)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Muscles hit")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                Text(line)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DGColor.ink3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            TrainChevron()
        }
        .padding(DGSpace.s4)
        .dgTile(radius: 20, opacity: 0.66)
        .accessibilityElement(children: .combine)
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
