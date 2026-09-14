import Foundation
import GymCore
import SwiftData

/// One earned milestone tier, formatted for display (the Summary's gold card and the
/// Milestones list). See `GymCore.Achievement` for the value this is built from.
struct AchievementInfo: Identifiable, Hashable {
    var id = UUID()
    var milestoneID: String
    var tier: Tier
    var title: String
    var line: String
}

extension WorkoutStore {
    /// Gathers the lifter's current numbers for `GymCore.Milestones.evaluate`/`progress`.
    /// `weeklyGoal` comes from `Preferences.weeklyGoal` and `calendar` from
    /// `Preferences.trainingCalendar` — the store itself doesn't read preferences, so every
    /// caller passes both explicitly.
    func milestoneState(weeklyGoal: Int, calendar: Calendar = .current) -> MilestoneState {
        let dates = workoutDates()
        let streak = Streaks.weekly(
            workoutDates: dates, weeklyGoal: weeklyGoal, calendar: calendar, now: Date()
        )
        let stats = lifetimeStats()
        return MilestoneState(
            workoutCount: stats.workouts, streakWeeks: streak.longest, lifetimeTonnageKg: stats.volumeKg,
            consistentWeeks: consistentWeekCount(dates: dates, weeklyGoal: weeklyGoal, calendar: calendar),
            bodyweightKg: latestBodyMeasurement()?.bodyweightKg, bestE1RM: bestE1RMByExerciseKey()
        )
    }

    /// Every tier newly crossed by finishing `workout`, persisted immediately so they're never
    /// re-celebrated. Backfilled/past-dated workouts still earn milestones (per plan.md §7); it's
    /// only the celebration animation that's gated separately, by `Milestones.isCelebrationWorthy`.
    @discardableResult
    func evaluateMilestones(
        for workout: WorkoutModel, weeklyGoal: Int, calendar: Calendar = .current, unit: WeightUnit = .kg
    ) -> [AchievementInfo] {
        let state = milestoneState(weeklyGoal: weeklyGoal, calendar: calendar)
        let earned = earnedTiers()
        let newlyEarned = Milestones.evaluate(
            state: state, earned: earned.map { (id: $0.key, tier: $0.value) }, unit: unit
        )
        for achievement in newlyEarned {
            let model = AchievementModel(
                milestoneID: achievement.id, tier: Self.tierString(achievement.tier), earnedAt: Date(),
                workoutID: workout.id
            )
            context.insert(model)
        }
        if !newlyEarned.isEmpty { save() }
        return newlyEarned.map(Self.achievementInfo)
    }

    /// Every milestone ever earned, newest first, "Earned 12 Sep"-style line.
    func achievements() -> [AchievementInfo] {
        let descriptor = FetchDescriptor<AchievementModel>(
            sortBy: [SortDescriptor(\.earnedAt, order: .reverse)]
        )
        let models = fetch(descriptor)
        return models.compactMap { model -> AchievementInfo? in
            guard let tier = Self.tier(from: model.tier),
                  let definition = Milestones.definitions.first(where: { $0.id == model.milestoneID }) else {
                return nil
            }
            return AchievementInfo(
                milestoneID: model.milestoneID, tier: tier, title: definition.title,
                line: "Earned \(Self.earnedDateLabel(model.earnedAt))"
            )
        }
    }

    /// Every milestone's current standing, earned or not, for `MilestonesView`'s grid.
    func milestoneProgress(weeklyGoal: Int, calendar: Calendar = .current) -> [MilestoneProgress] {
        Milestones.progress(state: milestoneState(weeklyGoal: weeklyGoal, calendar: calendar))
    }

    // MARK: - Helpers

    /// The highest earned tier per milestone id, from every persisted `AchievementModel`.
    private func earnedTiers() -> [String: Tier] {
        let models = fetch(FetchDescriptor<AchievementModel>())
        var result: [String: Tier] = [:]
        for model in models {
            guard let tier = Self.tier(from: model.tier) else { continue }
            if let existing = result[model.milestoneID], existing >= tier { continue }
            result[model.milestoneID] = tier
        }
        return result
    }

    /// Weeks (anywhere in history, not necessarily consecutive) that met `weeklyGoal`.
    private func consistentWeekCount(dates: [Date], weeklyGoal: Int, calendar: Calendar) -> Int {
        guard weeklyGoal > 0 else { return 0 }
        var counts: [Date: Int] = [:]
        for date in dates {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            counts[start, default: 0] += 1
        }
        return counts.values.filter { $0 >= weeklyGoal }.count
    }

    /// Best cached e1RM per `strengthRatio` exercise key ("bench"/"squat"/"deadlift"/"ohp"),
    /// matched by a small substring map over the exercise name.
    private func bestE1RMByExerciseKey() -> [String: Double] {
        let kind = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordModel> { $0.kind == kind }
        let models = fetch(FetchDescriptor(predicate: predicate))
        var result: [String: Double] = [:]
        for model in models {
            guard let exerciseID = model.exerciseID, let exercise = fetchExerciseModel(id: exerciseID),
                  let key = Self.exerciseKey(name: exercise.name) else { continue }
            result[key] = max(result[key] ?? 0, model.value)
        }
        return result
    }

    private static func exerciseKey(name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("bench press") { return "bench" }
        if lower.contains("squat") { return "squat" }
        if lower.contains("deadlift") { return "deadlift" }
        if lower.contains("overhead press") || lower.contains("shoulder press") { return "ohp" }
        return nil
    }

    private static func achievementInfo(_ achievement: Achievement) -> AchievementInfo {
        AchievementInfo(
            milestoneID: achievement.id, tier: achievement.tier, title: achievement.title,
            line: achievement.line
        )
    }

    private static func tierString(_ tier: Tier) -> String {
        switch tier {
        case .bronze: return "bronze"
        case .silver: return "silver"
        case .gold: return "gold"
        }
    }

    private static func tier(from raw: String) -> Tier? {
        switch raw {
        case "bronze": return .bronze
        case "silver": return .silver
        case "gold": return .gold
        default: return nil
        }
    }

    private static func earnedDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
