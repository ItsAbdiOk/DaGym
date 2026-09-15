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
    ///
    /// `finishedWorkouts` (newest first, this workout included) lets `finish` hand over the
    /// list it already read rather than have the dates and lifetime totals fetched again.
    func milestoneState(
        weeklyGoal: Int, calendar: Calendar = .current, finishedWorkouts: [WorkoutModel]? = nil
    ) -> MilestoneState {
        let dates = workoutDates(finishedWorkouts: finishedWorkouts)
        let streak = Streaks.weekly(
            workoutDates: dates, weeklyGoal: weeklyGoal, calendar: calendar, now: Date()
        )
        let stats = lifetimeStats(finishedWorkouts: finishedWorkouts)
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
        for workout: WorkoutModel, weeklyGoal: Int, calendar: Calendar = .current, unit: WeightUnit = .kg,
        finishedWorkouts: [WorkoutModel]? = nil
    ) -> [AchievementInfo] {
        let state = milestoneState(
            weeklyGoal: weeklyGoal, calendar: calendar, finishedWorkouts: finishedWorkouts
        )
        let earned = earnedTiers()
        let newlyEarned = Milestones.evaluate(
            state: state, earned: earned.map { (id: $0.key, tier: $0.value) }, unit: unit
        )
        // Stamped with the session that earned it, not with "now". A lifter backfilling six
        // months of training had every badge dated today, so the milestones list read as though
        // they had earned a Gold streak on the afternoon they typed it in.
        let earnedAt = min(workout.startedAt, Date())
        for achievement in newlyEarned {
            let model = AchievementModel(
                milestoneID: achievement.id, tier: Self.tierString(achievement.tier),
                earnedAt: earnedAt, workoutID: workout.id
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
    ///
    /// Counts distinct training **days** per week, matching `Streaks.weekly`: two sessions on one
    /// Saturday are one day toward "4 a week", not two.
    private func consistentWeekCount(dates: [Date], weeklyGoal: Int, calendar: Calendar) -> Int {
        guard weeklyGoal > 0 else { return 0 }
        var daysPerWeek: [Date: Set<Date>] = [:]
        for date in dates {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            daysPerWeek[start, default: []].insert(calendar.startOfDay(for: date))
        }
        return daysPerWeek.values.filter { $0.count >= weeklyGoal }.count
    }

    /// Best cached e1RM per `strengthRatio` exercise key ("bench"/"squat"/"deadlift"/"ohp"),
    /// matched on the exercise's **identity**.
    private func bestE1RMByExerciseKey() -> [String: Double] {
        let kind = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordModel> { $0.kind == kind }
        let models = fetch(FetchDescriptor(predicate: predicate))
        var result: [String: Double] = [:]
        for model in models {
            guard let exerciseID = model.exerciseID, let exercise = fetchExerciseModel(id: exerciseID),
                  let key = Self.exerciseKey(
                      seedID: exercise.seedID, name: exercise.name, equipment: exercise.equipment
                  ) else { continue }
            result[key] = max(result[key] ?? 0, model.value)
        }
        return result
    }

    /// The seeded exercises that *are* the four tracked barbell lifts. A "Bodyweight Squat"
    /// milestone has to mean the barbell squat and nothing else.
    ///
    /// Matching on `name.contains("squat")` meant a hack squat at 180 × 5 earned **Gold**
    /// "Bodyweight Squat", a Romanian deadlift (a hip hinge done at a fraction of a pull) earned
    /// Silver deadlift, and a dumbbell shoulder press counted as the barbell press at half the
    /// load — because a dumbbell's `weightKg` is one bell.
    private static let strengthSeedIDs: [String: String] = [
        // bench
        "Barbell_Bench_Press_-_Medium_Grip": "bench",
        "Bench_Press_-_Powerlifting": "bench",
        "Pause_Bench": "bench",
        // squat
        "Barbell_Squat": "squat",
        "Barbell_Full_Squat": "squat",
        // deadlift
        "Barbell_Deadlift": "deadlift",
        "Deadlifts": "deadlift",
        "Sumo_Deadlift": "deadlift",
        // overhead press
        "Barbell_Shoulder_Press": "ohp",
        "Standing_Military_Press": "ohp",
        "Overhead_Barbell_Press": "ohp"
    ]

    /// Exact names, for a custom or imported exercise with no `seedID`. Paired with an equipment
    /// check so a "Squat" logged as a bodyweight move can never qualify.
    private static let strengthNames: [String: String] = [
        "bench press": "bench", "barbell bench press": "bench", "flat bench press": "bench",
        "squat": "squat", "back squat": "squat", "barbell squat": "squat", "high bar squat": "squat",
        "low bar squat": "squat",
        "deadlift": "deadlift", "barbell deadlift": "deadlift", "conventional deadlift": "deadlift",
        "sumo deadlift": "deadlift",
        "overhead press": "ohp", "barbell overhead press": "ohp", "military press": "ohp",
        "strict press": "ohp"
    ]

    private static func exerciseKey(seedID: String?, name: String, equipment: String) -> String? {
        if let seedID, let key = strengthSeedIDs[seedID] { return key }
        guard seedID == nil, equipment.lowercased() == "barbell" else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return strengthNames[trimmed]
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

    /// One formatter for every achievement row, not one per row. `CoachFactsSource` keeps the
    /// same `"d MMM"` format; a shared cache is consolidated later.
    private static let earnedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static func earnedDateLabel(_ date: Date) -> String {
        earnedDateFormatter.string(from: date)
    }
}
