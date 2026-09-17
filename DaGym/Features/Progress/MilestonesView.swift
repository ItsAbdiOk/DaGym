import GymCore
import SwiftData
import SwiftUI

/// Milestones as a card: "14 of 32 earned", then one row per milestone — a tinted trophy
/// circle (tier colour once earned, a low ink while locked), the title over a progress bar to
/// the next tier, and the percentage. Earned ones first. Tapping a row opens every tier.
struct MilestonesCard: View {
    var generation = 0

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var progress: [MilestoneProgress] = []
    @State private var achievements: [AchievementInfo] = []
    @State private var selected: MilestoneProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressCardTitle(title: "Milestones")
                Text("\(earned.count) of \(progress.count) earned")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
            }
            VStack(spacing: 10) {
                ForEach(earned + locked) { item in
                    MilestoneRow(item: item, subtitle: subtitle(for: item)) { selected = item }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard(radius: 20, padding: DGSpace.s4)
        .task(id: generation) { refresh() }
        .sheet(item: $selected) { item in
            MilestoneDetailSheet(
                item: item, achievements: achievements.filter { $0.milestoneID == item.id },
                unit: preferences.weightUnit
            )
        }
    }

    private var earned: [MilestoneProgress] { progress.filter { $0.currentTier != nil } }
    private var locked: [MilestoneProgress] { progress.filter { $0.currentTier == nil } }

    private func subtitle(for item: MilestoneProgress) -> String {
        achievements.first { $0.milestoneID == item.id && $0.tier == item.currentTier }?.line
            ?? MilestoneCopy.lockedSubtitle(
                metric: item.definition.metric, nextThreshold: item.nextThreshold,
                unit: preferences.weightUnit
            )
    }

    private func refresh() {
        let weeklyGoal = preferences.weeklyGoal
        progress = store.milestoneProgress(weeklyGoal: weeklyGoal, calendar: preferences.trainingCalendar)
        achievements = store.achievements()
    }
}

/// Milestones as a pushed screen of its own (the Progress hub's row, the screenshot list).
struct MilestonesView: View {
    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                MilestonesCard()
                    .padding(.horizontal, DGSpace.s4)
                    .padding(.top, DGSpace.s3)
                    .padding(.bottom, DGSpace.s8)
            }
        }
        .navigationTitle("Milestones")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Locked/threshold copy for a milestone, unit-aware for the metrics that carry a weight.
/// Pulled out of the view so it's testable without a store or SwiftUI.
enum MilestoneCopy {
    static func lockedSubtitle(metric: MilestoneMetric, nextThreshold: Double?, unit: WeightUnit) -> String {
        guard let nextThreshold else { return "Every tier earned" }
        switch metric {
        case .strengthRatio:
            return "Need \(RatioFormat.plain(nextThreshold))× bodyweight"
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
        case .strengthRatio: return "\(RatioFormat.plain(threshold))× bodyweight"
        case .workoutCount: return "\(Int(threshold)) workouts"
        case .streakWeeks: return "\(Int(threshold))-week streak"
        case .lifetimeTonnageKg: return "\(unit.format(kg: threshold)) \(unit.symbol) lifetime"
        case .consistencyWeeks: return "\(Int(threshold)) weeks at goal"
        }
    }
}

/// One milestone row: trophy circle, title, subtitle, progress bar, percent.
private struct MilestoneRow: View {
    var item: MilestoneProgress
    var subtitle: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Circle()
                    .fill(tierColor)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: item.currentTier != nil ? "trophy.fill" : "lock.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(item.currentTier != nil ? .white : DGColor.ink3)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.definition.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DGColor.ink1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DGColor.ink3)
                        .lineLimit(1)
                    progressBar
                }
                Text("\(Int((item.progress * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
        .accessibilityElement(children: .combine)
        // The bar is hidden; say what it shows.
        .accessibilityValue("\(Int((item.progress * 100).rounded())) percent to next tier")
    }

    private var progressBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(DGColor.ink1.opacity(0.09))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(item.currentTier != nil ? tierColor : DGColor.coral)
                        .frame(width: geo.size.width * item.progress)
                }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var tierColor: Color {
        switch item.currentTier {
        case .bronze: DGColor.prGoldDeep
        case .silver: DGColor.ink3
        case .gold: DGColor.prGold
        case nil: DGColor.ink1.opacity(0.08)
        }
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
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.displayName).dgLabel(earnedLine != nil ? tierColor : DGColor.ink3)
                Text(earnedLine ?? "Locked · \(thresholdLabel)")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink1)
            }
            Spacer()
        }
        .frame(minHeight: DGTap.min)
        .accessibilityElement(children: .combine)
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
