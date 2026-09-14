import GymCore
import SwiftData
import SwiftUI

/// Milestones — a grid of every bronze/silver/gold tier the app tracks (plan.md §6.4, §7),
/// earned ones up top in their tier colour, locked ones with a progress bar to the next tier.
struct MilestonesView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var progress: [MilestoneProgress] = []
    @State private var achievements: [AchievementInfo] = []
    @State private var selected: MilestoneProgress?

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    VStack(spacing: DGSpace.s3) {
                        ForEach(earned) { item in
                            MilestoneCard(
                                item: item, earnedLine: earnedLine(for: item), unit: preferences.weightUnit
                            ) { selected = item }
                        }
                        ForEach(locked) { item in
                            MilestoneCard(
                                item: item, earnedLine: nil, unit: preferences.weightUnit
                            ) { selected = item }
                        }
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .task { refresh() }
        .sheet(item: $selected) { item in
            MilestoneDetailSheet(
                item: item, achievements: achievements.filter { $0.milestoneID == item.id },
                unit: preferences.weightUnit
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text("Milestones")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("\(earned.count) of \(progress.count) earned")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
    }

    private var earned: [MilestoneProgress] { progress.filter { $0.currentTier != nil } }
    private var locked: [MilestoneProgress] { progress.filter { $0.currentTier == nil } }

    private func earnedLine(for item: MilestoneProgress) -> String? {
        achievements.first { $0.milestoneID == item.id && $0.tier == item.currentTier }?.line
    }

    private func refresh() {
        let weeklyGoal = preferences.weeklyGoal
        progress = store.milestoneProgress(weeklyGoal: weeklyGoal, calendar: preferences.trainingCalendar)
        achievements = store.achievements()
    }
}

/// Locked/threshold copy for a milestone, unit-aware for the metrics that carry a weight.
/// Pulled out of the view so it's testable without a store or SwiftUI.
enum MilestoneCopy {
    static func lockedSubtitle(metric: MilestoneMetric, nextThreshold: Double?, unit: WeightUnit) -> String {
        guard let nextThreshold else { return "Every tier earned" }
        switch metric {
        case .strengthRatio:
            return "Need \(WeightFormat.kg(nextThreshold))× bodyweight"
        case .workoutCount:
            return "Need \(Int(nextThreshold)) workouts"
        case .streakWeeks:
            return "Need a \(Int(nextThreshold))-week streak"
        case .lifetimeTonnageKg:
            return "Need \(unit.format(kg: nextThreshold)) \(unit.symbol) lifetime"
        case .consistencyWeeks:
            return "Need \(Int(nextThreshold)) weeks at your goal"
        }
    }

    static func thresholdLabel(metric: MilestoneMetric, threshold: Double, unit: WeightUnit) -> String {
        switch metric {
        case .strengthRatio: return "\(WeightFormat.kg(threshold))× bodyweight"
        case .workoutCount: return "\(Int(threshold)) workouts"
        case .streakWeeks: return "\(Int(threshold))-week streak"
        case .lifetimeTonnageKg: return "\(unit.format(kg: threshold)) \(unit.symbol) lifetime"
        case .consistencyWeeks: return "\(Int(threshold)) weeks at goal"
        }
    }
}

/// One milestone card: tier badge (earned) or a lock (locked), title, subtitle, progress bar.
private struct MilestoneCard: View {
    var item: MilestoneProgress
    var earnedLine: String?
    var unit: WeightUnit
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: DGSpace.s3) {
                badge
                VStack(alignment: .leading, spacing: DGSpace.s1) {
                    Text(item.definition.title.uppercased())
                        .font(DGFont.title3)
                        .foregroundStyle(item.currentTier != nil ? tierColor : DGColor.ink1)
                    Text(earnedLine ?? lockedSubtitle)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.currentTier == nil || item.nextThreshold != nil { progressBar }
                }
                Spacer(minLength: 0)
            }
            .padding(DGSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.dgCard)
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
            .fill(item.currentTier != nil ? tierColor : DGColor.surface3)
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: item.currentTier != nil ? "star.fill" : "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.currentTier != nil ? DGColor.inkOnCoral : DGColor.ink3)
            }
            .accessibilityHidden(true)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DGColor.surface3)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.currentTier != nil ? tierColor : DGColor.coral)
                        .frame(width: geo.size.width * item.progress)
                }
        }
        .frame(height: 6)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private var lockedSubtitle: String {
        MilestoneCopy.lockedSubtitle(
            metric: item.definition.metric, nextThreshold: item.nextThreshold, unit: unit
        )
    }

    private var tierColor: Color {
        switch item.currentTier {
        case .bronze: return DGColor.prGoldDeep
        case .silver: return DGColor.ink3
        case .gold: return DGColor.prGold
        case nil: return DGColor.ink3
        }
    }

    private var cardFill: Color {
        item.currentTier != nil ? tierColor.opacity(0.10) : DGColor.surface2
    }

    private var cardStroke: Color {
        item.currentTier != nil ? tierColor.opacity(0.35) : DGColor.hairline
    }
}

/// Every tier of one milestone, tapped in from the grid.
private struct MilestoneDetailSheet: View {
    var item: MilestoneProgress
    var achievements: [AchievementInfo]
    var unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            Text(item.definition.title).dgLabel()
            VStack(spacing: DGSpace.s3) {
                ForEach(item.definition.tiers, id: \.tier) { tier, threshold in
                    TierRow(
                        tier: tier, threshold: threshold, metric: item.definition.metric,
                        earnedLine: achievements.first { $0.tier == tier }?.line, unit: unit
                    )
                }
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, DGSpace.s6)
        .padding(.bottom, DGSpace.s6)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
    }
}

/// One tier line inside the detail sheet: badge, threshold description, earned date or "Locked".
private struct TierRow: View {
    var tier: Tier
    var threshold: Double
    var metric: MilestoneMetric
    var earnedLine: String?
    var unit: WeightUnit

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Image(systemName: earnedLine != nil ? "star.fill" : "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(earnedLine != nil ? tierColor : DGColor.ink4)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.displayName).dgLabel(earnedLine != nil ? tierColor : DGColor.ink3)
                Text(earnedLine ?? "Locked · \(thresholdLabel)")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer()
        }
        .frame(minHeight: DGTap.min)
    }

    private var thresholdLabel: String {
        MilestoneCopy.thresholdLabel(metric: metric, threshold: threshold, unit: unit)
    }

    private var tierColor: Color {
        switch tier {
        case .bronze: return DGColor.prGoldDeep
        case .silver: return DGColor.ink3
        case .gold: return DGColor.prGold
        }
    }
}

#Preview {
    if let container = try? ModelContainer.dagym(inMemory: true) {
        MilestonesView()
            .environment(WorkoutStore(context: container.mainContext))
            .environment(Preferences())
    } else {
        Text("Preview unavailable")
    }
}
