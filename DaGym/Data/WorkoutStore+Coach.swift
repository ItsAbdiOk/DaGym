import Foundation
import GymCore
import SwiftData

/// Assembles `GymCore.CoachInput` from SwiftData — the only place SwiftData meets `CoachEngine`
/// (see `Coach/CoachInput.swift`, `Coach/CoachEngine.swift`). Every rule's own math stays in
/// `GymCore/Coach`; this file only gathers the numbers each field's doc comment on `CoachInput`
/// already says it needs, reusing existing store accessors (`schedule()`, `bodySeries`,
/// `recoverySnapshot()`, `exerciseHistory`, `substitutionCandidates()`, `hardWeekStreak`) rather
/// than writing new queries. Applying an approved card lives in `WorkoutStore+CoachActions.swift`.
///
/// `now` and `calendar` are threaded all the way down. The engine is pure by construction; this
/// adapter has to be pure over `(store, now, calendar)` too, or a test that pins `now` still gets
/// a different answer tomorrow.
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
                weeklyGoal: weeklyGoal, calendar: calendar, now: now, finishedWorkouts: finishedWorkouts
            ),
            substitutionLibrary: substitutionCandidates(),
            availableEquipment: Set(activeProfile()?.availableEquipment ?? []),
            recoveryMap: recoverySnapshot(now: now, calendar: calendar).map,
            recentPRs: recentPRHighlights(now: now),
            recentAchievements: recentAchievementHighlights(now: now),
            lastWorkoutDate: finishedWorkouts.first?.startedAt,
            interactions: coachInteractions()
        )
    }

    // MARK: - Interactions (persisted dismissals/approvals)

    /// Every persisted Approve/Dismiss, for `CoachInput.interactions` — `CoachEngine` does its own
    /// cooldown-window filtering against this list. Home's "Why a deload?" card reads and writes
    /// the same rows (`WorkoutStore+Deload.swift`), so a dismissal in one place holds in both.
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
    /// screen's Undo toast) can remove exactly this row if the lifter undoes it.
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
    /// progression baseline already accepts.
    ///
    /// Zero for a freestyle session or a since-deleted routine, which is how
    /// `CoachRules.sessionDriftCards` is told "no set signal here, skip me". It used to fall back
    /// to the completed count, which is a perfect 1.0 ratio — so every freestyle session quietly
    /// raised the baseline that the lifter's planned sessions were then judged against.
    private func plannedSetCount(for workout: WorkoutModel) -> Int {
        guard let routineID = workout.routineID, let routine = fetchRoutineModel(id: routineID) else {
            return 0
        }
        let exerciseIDs = Set((workout.exercises ?? []).compactMap { $0.exercise?.id })
        return (routine.exercises ?? [])
            .filter { $0.exercise.map { exerciseIDs.contains($0.id) } ?? false }
            .reduce(0) { $0 + ($1.plannedSets?.filter { $0.setKind.countsTowardStats }.count ?? 0) }
    }

    /// The routines the lifter is actually running: the active program's, or failing that the
    /// scheduled ones, or failing that every non-archived routine. Nil means "no filter".
    /// A routine that is neither programmed nor scheduled is a draft or a leftover, and the
    /// coverage rule must not report a gap in training the lifter never intended to do.
    private func programmeRoutineIDs() -> Set<UUID>? {
        if let program = activeProgramModel(), !program.routineIDs.isEmpty {
            return Set(program.routineIDs)
        }
        let plan = schedule()
        let scheduled = Set(plan.dayRoutines.values.flatMap { $0 } + plan.dateOverrides.values.flatMap { $0 })
        return scheduled.isEmpty ? nil : scheduled
    }

    /// Every routine-exercise slot in the running programme, non-archived routines only.
    private func programmeRoutineExercises() -> [RoutineExerciseModel] {
        let models = (try? context.fetch(FetchDescriptor<RoutineExerciseModel>())) ?? []
        let allowed = programmeRoutineIDs()
        return models.filter { model in
            guard let routine = model.routine, !routine.isArchived else { return false }
            return allowed.map { $0.contains(routine.id) } ?? true
        }
    }

    /// Every muscle the running programme trains as a **primary** mover — deliberately not
    /// `Muscle.allCases` (per `CoachInput.trackedMuscles`'s contract), and deliberately not
    /// secondary movers either: `BodySeries.setsPerMuscle` weights a secondary mover at 0.5, so
    /// a muscle that only ever gets incidental work sits at 1.5 sets against a floor of 4 forever
    /// and would report a permanent "gap" in a plan that is going exactly as written.
    private func trackedMuscles() -> [Muscle] {
        var seen = Set<Muscle>()
        var ordered: [Muscle] = []
        for model in programmeRoutineExercises() {
            guard let exercise = model.exercise else { continue }
            for muscle in exercise.primary where !seen.contains(muscle) {
                seen.insert(muscle)
                ordered.append(muscle)
            }
        }
        return ordered
    }

    /// One `CoachLiftSnapshot` per distinct exercise in the running programme, deduped by
    /// exercise id (a lift shared by two routines is one lift to the coach, not two).
    /// Not private: `deloadSuggestion` builds Home's card from exactly these snapshots, so both
    /// screens name the same lifts (`WorkoutStore+Deload.swift`).
    func coachLiftSnapshots(finishedWorkouts: [WorkoutModel]) -> [CoachLiftSnapshot] {
        var byExerciseID: [UUID: RoutineExerciseModel] = [:]
        for routineExercise in programmeRoutineExercises() {
            guard let exercise = routineExercise.exercise else { continue }
            // Prefer an entry that actually has planned sets, in case the same exercise sits in
            // two routines and one is still mid-edit.
            if let existing = byExerciseID[exercise.id], !(existing.plannedSets ?? []).isEmpty { continue }
            byExerciseID[exercise.id] = routineExercise
        }
        // Resolved once for the whole set rather than per lift — it's a store query.
        let equipment = activeEquipment()
        return byExerciseID.values
            .compactMap {
                liftSnapshot(
                    routineExercise: $0, finishedWorkouts: finishedWorkouts, equipment: equipment
                )
            }
            .sorted { $0.name < $1.name }
    }

    private func liftSnapshot(
        routineExercise: RoutineExerciseModel, finishedWorkouts: [WorkoutModel],
        equipment: ProgressionEquipment
    ) -> CoachLiftSnapshot? {
        guard let exerciseModel = routineExercise.exercise else { return nil }
        let history = exerciseHistory(
            exerciseID: exerciseModel.id, limit: Self.coachHistoryWindow, finishedWorkouts: finishedWorkouts
        )
        // Oldest first for the trend arrays, and never a planned deload's lower numbers — the
        // documented contract `CoachLiftSnapshot.e1rmTrend` shares with
        // `DeloadDetector.LiftSnapshot.e1rmTrend`. Trimmed to the window the rules are specified
        // over: `DeloadDetector.isNotProgressing` compares the first point against the last, so a
        // 16-session array turned "you were stronger four months ago" into "not progressing".
        let window = TrainingConstants.coachE1rmDowntrendSessions
        let nonDeload = history.filter { !$0.wasPlannedDeload }.reversed()
        let e1rms = nonDeload.compactMap { entry in
            entry.workingSets.compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }.max()
        }
        let rpes = nonDeload.compactMap { $0.workingSets.first?.effort?.rpe }
        let lastWorking = history.first?.workingSets ?? []
        let info = exerciseInfo(for: exerciseModel)
        return CoachLiftSnapshot(
            name: exerciseModel.name,
            exerciseID: exerciseModel.id,
            stallState: routineExercise.stallStateValue,
            e1rmTrend: Array(e1rms.suffix(window)),
            rpeAtSameLoadTrend: rpes.isEmpty ? nil : Array(rpes.suffix(window)),
            loadGrid: loadGrid(for: info, equipment: equipment),
            lastWorkingWeightKg: lastWorking.first?.weightKg,
            lastWorkingSetCount: lastWorking.isEmpty ? nil : lastWorking.count,
            consecutiveFailedSessions: consecutiveFailedSessions(
                history: history, plannedSets: routineExercise.plannedSets ?? []
            ),
            substitutionCandidate: substitutionCandidate(for: exerciseModel)
        )
    }

    /// Sessions in a row (most recent first, stopping at the first clean one) where every logged
    /// working set came up short of this lift's own current rep target.
    ///
    /// Deliberately narrower than it was, because three of its old inputs weren't evidence:
    ///  * `SetKind.failure` is the "to failure" *technique*, not a failed set. Anyone programming
    ///    one was flagged every single week. Those sets are now excluded from the judgement.
    ///  * A timed hold logs `reps == 0`, so "reps under target" was permanently true for it. A
    ///    plan with any timed target isn't judged at all — there is no rep target to judge.
    ///  * A session where the lift simply wasn't logged never reaches `history`, so a genuinely
    ///    skipped session is invisible here. The card's copy says "short of its target"
    ///    accordingly, not "missed or skipped".
    ///
    /// The target is the *low* end of the plan's rep range (`targetReps`; `targetRepsHigh` is the
    /// top of the range, not the bar to clear), taken as the minimum across working sets so a
    /// heavier top set isn't judged against a back-off set's easier target.
    private func consecutiveFailedSessions(
        history: [ExerciseHistoryEntry], plannedSets: [PlannedSetModel]
    ) -> Int {
        let working = plannedSets.filter { $0.setKind.countsTowardStats }
        guard working.allSatisfy({ $0.targetSeconds == nil }),
              let target = working.compactMap(\.targetReps).min(), target > 0 else { return 0 }
        var streak = 0
        for entry in history {
            let judged = entry.workingSets.filter { $0.kind != .failure }
            guard !judged.isEmpty, (judged.map(\.reps).max() ?? 0) < target else { break }
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

    static func outcomeString(_ outcome: CoachInteraction.Outcome) -> String {
        switch outcome {
        case .dismissed: return "dismissed"
        case .approved: return "approved"
        }
    }

    static func outcome(from raw: String) -> CoachInteraction.Outcome? {
        switch raw {
        case "dismissed": return .dismissed
        case "approved": return .approved
        default: return nil
        }
    }
}
