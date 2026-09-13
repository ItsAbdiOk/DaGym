import Foundation
import SwiftData

/// One earned milestone tier (`GymCore.Achievement`), persisted so it's never re-celebrated.
@Model
final class AchievementModel {
    var id: UUID = UUID()
    /// `GymCore.MilestoneDefinition.id`, e.g. "strength.bench" or "workoutCount".
    var milestoneID: String = ""
    /// "bronze" / "silver" / "gold" (`GymCore.Tier.rawValue`).
    var tier: String = "bronze"
    var earnedAt: Date = Date()
    /// The workout that earned it, when there is one (a milestone can also cross a threshold
    /// without a fresh workout, e.g. after a Health bodyweight sync).
    var workoutID: UUID?

    init(
        id: UUID = UUID(), milestoneID: String = "", tier: String = "bronze", earnedAt: Date = Date(),
        workoutID: UUID? = nil
    ) {
        self.id = id
        self.milestoneID = milestoneID
        self.tier = tier
        self.earnedAt = earnedAt
        self.workoutID = workoutID
    }
}
