import Foundation
import GymCore
import SwiftData

/// Assembles `GymCore.CoachInput` from SwiftData and applies the coach's approvable actions back
/// onto the store — the only place SwiftData meets `CoachEngine` (see `Coach/CoachInput.swift`,
/// `Coach/CoachEngine.swift`). Every rule's own math stays in `GymCore/Coach`; this file only
/// gathers the numbers each field's doc comment on `CoachInput` already says it needs, reusing
/// existing store accessors (`schedule()`, `bodySeries`, `recoverySnapshot()`, `exerciseHistory`,
/// `substitutionCandidates()`, `hardWeekStreak`) rather than writing new queries.
extension WorkoutStore {
    /// How many finished workouts back the session-drift and per-lift windows look. Covers
    /// `coachDriftRecentSessions + coachDriftBaselineSessions` (12) with headroom, and is generous
    /// enough for `coachE1rmDowntrendSessions` (4, after excluding planned deloads) too.
    private static let coachHistoryWindow = 16
    private static let coachRecentHighlightDays = 14.0

    /// `CoachEngine.cards(for:now:calendar:)`'s active cards, built from the store's current
    /// state. `weeklyGoal`/`calendar` come from `Preferences`, same as `milestoneState` and
    /// `deloadSuggestion` — the store itself never reads preferences.
    func coachCards(weeklyGoal: Int = 4, now: Date = Date(), calendar: Calendar = .current) -> [CoachCard] {
        let input = coachInput(weeklyGoal: weeklyGoal, now: now, calendar: calendar)
        return CoachEngine.cards(for: input, now: now, calendar: calendar)
    }

    /// The `CoachInput` `coachCards` feeds the engine — exposed separately so a test can inspect
    /// what was assembled without also exercising the ten rules.
    func coachInput(weeklyGoal: Int = 4, now: Date = Date(), calendar: Calendar = .current) -> CoachInput {
        // Fetched once and shared with every per-lift/per-session lookup below — the same
        // "one fetch, reused" pattern `persistProgression`/`deloadSuggestion` already use (see
        // `WorkoutStore+Progression.swift`), rather than each lift re-querying the whole list.
        let finishedWorkouts = finishedWorkoutModelsNewestFirst()
        let recentWorkouts = Array(finishedWorkouts.prefix(Self.coachHistoryWindow))

        return CoachInput(
            schedule: schedule(),
            workoutDates: workoutDates(),
            recentSessions: recentSessions(from: recentWorkouts),
            muscleSetsInWindow: bodySeries(
                weeks: 1, calendar: calendar,
                balanceWindow: .days(TrainingConstants.coachCoverageWindowDays), now: now
            ).setsPerMuscle,
            trackedMuscles: trackedMuscles(),
            lifts: coachLiftSnapshots(finishedWorkouts: finishedWorkouts),
            hardWeeksInARow: hardWeekStreak(
                weeklyGoal: weeklyGoal, calendar: calendar, finishedWorkouts: finishedWorkouts
            ),
            substitutionLibrary: substitutionCandidates(),
            availableEquipment: Set(activeProfile()?.availableEquipment ?? []),
            recoveryMap: recoverySnapshot(now: now).map,
            recentPRs: recentPRHighlights(now: now),
            recentAchievements: recentAchievementHighlights(now: now),
            lastWorkoutDate: finishedWorkouts.first?.startedAt,
            interactions: coachInteractions()
        )
    }

    // MARK: - Interactions (persisted dismissals/approvals)

    /// Every persisted Approve/Dismiss, for `CoachInput.interactions` — `CoachEngine` does its own
    /// cooldown-window filtering against this list.
    func coachInteractions() -> [CoachInteraction] {
        let models = (try? context.fetch(FetchDescriptor<CoachInteractionModel>())) ?? []
        return models.compactMap { model in
            guard let rule = CoachRule(rawValue: model.rule), let outcome = Self.outcome(from: model.outcome)
            else { return nil }
            return CoachInteraction(
                rule: rule, fingerprint: model.fingerprint, outcome: outcome, date: model.date
            )
        }
    }

    /// Records one Approve/Dismiss, returning the inserted model's id so the caller (the Coach
    /// screen's Undo toast) can remove exactly this row if the lifter undoes a dismissal.
    @discardableResult
    func recordCoachInteraction(
        rule: CoachRule, fingerprint: String, outcome: CoachInteraction.Outcome, date: Date = Date()
    ) -> UUID {
        let model = CoachInteractionModel(
            rule: rule.rawValue, fingerprint: fingerprint, outcome: Self.outcomeString(outcome), date: date
        )
        context.insert(model)
        save()
        return model.id
    }

    /// Undoes exactly one `recordCoachInteraction` call, by the id it returned.
    func removeCoachInteraction(id: UUID) {
        var descriptor = FetchDescriptor<CoachInteractionModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let model = (try? context.fetch(descriptor))?.first else { return }
        context.delete(model)
        save()
    }

    // MARK: - Approvable actions

    /// Applying a `.deloadExercise` suggested action (the only one this adapter can carry out on
    /// its own, with no active workout to hand it to): lowers every routine's planned working-set
    /// weight for this exercise to the suggestion's load and resets its stall state there, so the
    /// next time it's trained it starts from the lighter number instead of resuming the stall.
    /// Returns whether a matching exercise was found. `CoachView` calls this from Approve; every
    /// other suggested action is recorded but not auto-applied (see its doc comment on
    /// `CoachSuggestedAction`) — there is no active session or screen this adapter can safely act
    /// through on its own.
    @discardableResult
    func applyCoachDeload(exerciseName: String, toWeightKg: Double) -> Bool {
        let routineExercises = (try? context.fetch(FetchDescriptor<RoutineExerciseModel>())) ?? []
        let matches = routineExercises.filter { $0.exercise?.name == exerciseName }
        guard !matches.isEmpty else { return false }
        for routineExercise in matches {
            for plannedSet in routineExercise.plannedSets ?? [] where plannedSet.setKind.countsTowardStats {
                plannedSet.targetWeightKg = toWeightKg
            }
            routineExercise.stallStateValue = routineExercise.stallStateValue.advancing(
                misses: 0, weightKg: toWeightKg
            )
        }
        save()
        return true
    }

    // MARK: - CoachInput assembly helpers

    private func recentSessions(from workouts: [WorkoutModel]) -> [CoachSessionSummary] {
        workouts.map { workout in
            let completed = (workout.exercises ?? []).flatMap { exercise in
                (exercise.sets ?? []).filter { $0.isCompleted && $0.setKind.countsTowardStats }
            }
            let duration = workout.endedAt.map { max(0, Int($0.timeIntervalSince(workout.startedAt))) } ?? 0
            return CoachSessionSummary(
                date: workout.startedAt, plannedSetCount: plannedSetCount(for: workout),
                completedSetCount: completed.count, durationSeconds: duration
            )
        }
    }

    /// The routine's *current* plan for the exercises this session actually logged — an
    /// approximation (the plan may have changed since), the same trade-off `exerciseHistory`'s
    /// progression baseline already accepts. Falls back to the completed count itself (a 1.0
    /// ratio, no drift signal either way) for a freestyle session or a since-deleted routine, so
    /// the session's duration signal isn't lost to a zero denominator.
    private func plannedSetCount(for workout: WorkoutModel) -> Int {
        let completedCount = (workout.exercises ?? []).flatMap { exercise in
            (exercise.sets ?? []).filter { $0.isCompleted && $0.setKind.countsTowardStats }
        }.count
        guard let routineID = workout.routineID, let routine = fetchRoutineModel(id: routineID) else {
            return completedCount
        }
        let exerciseIDs = Set((workout.exercises ?? []).compactMap { $0.exercise?.id })
        let planned = (routine.exercises ?? [])
            .filter { $0.exercise.map { exerciseIDs.contains($0.id) } ?? false }
            .reduce(0) { $0 + ($1.plannedSets?.filter { $0.setKind.countsTowardStats }.count ?? 0) }
        return planned > 0 ? planned : completedCount
    }

    /// Every muscle actually programmed by a non-archived routine right now — deliberately not
    /// `Muscle.allCases` (per `CoachInput.trackedMuscles`'s contract): a muscle this lifter has
    /// never trained shouldn't read as a coverage gap.
    private func trackedMuscles() -> [Muscle] {
        let models = (try? context.fetch(FetchDescriptor<RoutineExerciseModel>())) ?? []
        var seen = Set<Muscle>()
        var ordered: [Muscle] = []
        for model in models {
            guard let exercise = model.exercise, model.routine?.isArchived != true else { continue }
            for muscle in exercise.primary + exercise.secondary where !seen.contains(muscle) {
                seen.insert(muscle)
                ordered.append(muscle)
            }
        }
        return ordered
    }

    /// One `CoachLiftSnapshot` per distinct exercise across every non-archived routine, deduped by
    /// exercise id (a lift shared by two routines is one lift to the coach, not two).
    private func coachLiftSnapshots(finishedWorkouts: [WorkoutModel]) -> [CoachLiftSnapshot] {
        let routineExercises = (try? context.fetch(FetchDescriptor<RoutineExerciseModel>())) ?? []
        var byExerciseID: [UUID: RoutineExerciseModel] = [:]
        for routineExercise in routineExercises {
            guard let exercise = routineExercise.exercise, routineExercise.routine?.isArchived != true else {
                continue
            }
            // Prefer an entry that actually has planned sets, in case the same exercise sits in
            // two routines and one is still mid-edit.
            if let existing = byExerciseID[exercise.id], !(existing.plannedSets ?? []).isEmpty { continue }
            byExerciseID[exercise.id] = routineExercise
        }
        return byExerciseID.values
            .compactMap { liftSnapshot(routineExercise: $0, finishedWorkouts: finishedWorkouts) }
            .sorted { $0.name < $1.name }
    }

    private func liftSnapshot(
        routineExercise: RoutineExerciseModel, finishedWorkouts: [WorkoutModel]
    ) -> CoachLiftSnapshot? {
        guard let exerciseModel = routineExercise.exercise else { return nil }
        let history = exerciseHistory(
            exerciseID: exerciseModel.id, limit: Self.coachHistoryWindow, finishedWorkouts: finishedWorkouts
        )
        // Oldest first for the trend arrays, and never a planned deload's lower numbers — the
        // documented contract `CoachLiftSnapshot.e1rmTrend` shares with
        // `DeloadDetector.LiftSnapshot.e1rmTrend` (see `WorkoutStore+Deload.swift`'s
        // `liftSnapshot`, which this mirrors).
        let nonDeload = history.filter { !$0.wasPlannedDeload }.reversed()
        let e1rms = nonDeload.compactMap { entry in
            entry.workingSets.compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }.max()
        }
        let rpes = nonDeload.compactMap { $0.workingSets.first?.effort?.rpe }
        let lastWorking = history.first?.workingSets ?? []
        return CoachLiftSnapshot(
            name: exerciseModel.name,
            stallState: routineExercise.stallStateValue,
            e1rmTrend: e1rms,
            rpeAtSameLoadTrend: rpes.isEmpty ? nil : rpes,
            lastWorkingWeightKg: lastWorking.first?.weightKg,
            lastWorkingSetCount: lastWorking.isEmpty ? nil : lastWorking.count,
            consecutiveFailedSessions: consecutiveFailedSessions(
                history: history, plannedSets: routineExercise.plannedSets ?? []
            ),
            substitutionCandidate: substitutionCandidate(for: exerciseModel)
        )
    }

    /// Sessions in a row (most recent first, stopping at the first clean one) where this lift was
    /// either skipped, logged a `.failure`-kind set, or came up short of its own current planned
    /// rep target — an app-layer approximation of "struggling", since `HistorySet` doesn't carry
    /// the target it was judged against (only `StallState.consecutiveMisses`, which tracks a
    /// narrower "same weight, no progress" signal the stalled-lift rule already reads separately).
    private func consecutiveFailedSessions(
        history: [ExerciseHistoryEntry], plannedSets: [PlannedSetModel]
    ) -> Int {
        let targetReps = plannedSets.first { $0.setKind.countsTowardStats }?.targetReps
        var streak = 0
        for entry in history {
            let working = entry.workingSets
            let failed = working.contains { $0.kind == .failure }
            let missedTarget = targetReps.map { target in (working.map(\.reps).max() ?? 0) < target } ?? false
            guard failed || working.isEmpty || missedTarget else { break }
            streak += 1
        }
        return streak
    }

    private func recentPRHighlights(now: Date) -> [CoachPersonalRecordHighlight] {
        let since = now.addingTimeInterval(-Self.coachRecentHighlightDays * 86_400)
        // Headline (e1RM) only — the "one PR line per exercise" the rest of the app already
        // surfaces (see `WorkoutStore.prCount`'s doc comment).
        let headline = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordEventModel> {
            $0.kind == headline && $0.date >= since && $0.date <= now
        }
        let events = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        return events.compactMap { event -> CoachPersonalRecordHighlight? in
            guard let exerciseID = event.exerciseID, let exercise = fetchExerciseModel(id: exerciseID),
                  let kind = PRKind(rawValue: event.kind) else { return nil }
            let record = PersonalRecord(
                kind: kind, value: event.value, weightKg: event.weightKg, reps: event.reps, date: event.date
            )
            return CoachPersonalRecordHighlight(exerciseName: exercise.name, record: record)
        }
    }

    private func recentAchievementHighlights(now: Date) -> [CoachAchievementHighlight] {
        let since = now.addingTimeInterval(-Self.coachRecentHighlightDays * 86_400)
        let predicate = #Predicate<AchievementModel> { $0.earnedAt >= since && $0.earnedAt <= now }
        let models = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        return models.compactMap { model -> CoachAchievementHighlight? in
            guard let tier = Self.coachTier(from: model.tier),
                  let definition = Milestones.definitions.first(where: { $0.id == model.milestoneID })
            else { return nil }
            let achievement = Achievement(
                id: model.milestoneID, tier: tier, title: definition.title,
                line: "You earned \(definition.title) at \(tier.displayName) tier."
            )
            return CoachAchievementHighlight(achievement: achievement, date: model.earnedAt)
        }
    }

    private static func coachTier(from raw: String) -> Tier? {
        switch raw {
        case "bronze": return .bronze
        case "silver": return .silver
        case "gold": return .gold
        default: return nil
        }
    }

    private static func outcomeString(_ outcome: CoachInteraction.Outcome) -> String {
        switch outcome {
        case .dismissed: return "dismissed"
        case .approved: return "approved"
        }
    }

    private static func outcome(from raw: String) -> CoachInteraction.Outcome? {
        switch raw {
        case "dismissed": return .dismissed
        case "approved": return .approved
        default: return nil
        }
    }
}
