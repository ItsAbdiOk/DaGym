import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// Ends the session, computes PRs against the cache and returns a summary. Backfilled or
    /// otherwise earlier-dated workouts never claim a PR against a later-dated one.
    /// `weeklyGoal` (`Preferences.weeklyGoal`) and `calendar` (`Preferences.trainingCalendar`,
    /// whose `firstWeekday` defines "this week") feed the streak/consistency milestones; both
    /// are additive with defaults so existing call sites compile unchanged.
    func finish(
        session: WorkoutSession, weeklyGoal: Int = 4, calendar: Calendar = .current, unit: WeightUnit = .kg
    ) -> WorkoutSummary {
        sync(session: session)
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID) else {
            return WorkoutSummary(durationSeconds: 0, volumeKg: 0, setsDone: 0, prs: [], musclesHit: [:])
        }
        // A session is finished exactly once: a second call (double-tap, re-entrant sheet) would
        // otherwise re-run progression with this session now inside its own baseline and burn a
        // second stall. A backfill used to be exempt from this guard, because `startBackfill`
        // stamped its `endedAt` up front and there was no other way to tell it from a finished
        // one; it no longer does, so `endedAt` alone is the answer for every session.
        if workout.endedAt != nil {
            return summary(for: workout, session: session, prs: [], achievements: [])
        }
        // Computed with this session still excluded from `exerciseHistory` (its own `endedAt`
        // isn't stamped until after this) — the exact same baseline/stall `startWorkout` used to
        // prescribe this session, so this simply commits that already-shown result. Persisting
        // here rather than at start means abandoning a workout (never finishing) never burns a
        // stall (plan.md §6.5).
        persistProgression(session: session)
        pruneUnfinishedRows(of: workout)
        let now = Date()
        let endedAt = Self.endDate(for: workout, session: session, now: now)
        workout.endedAt = endedAt
        // The sets were stamped before the workout had an end; re-clamp them into the window it
        // has now, so `completedAt` always lands inside `[startedAt, endedAt]` (which is what
        // recovery decays from).
        for setModel in (workout.exercises ?? []).flatMap({ $0.sets ?? [] }) {
            guard let completedAt = setModel.completedAt else { continue }
            setModel.completedAt = Self.completionDate(completedAt, in: workout)
        }
        let prs = evaluatePRs(session: session, workout: workout, unit: unit)
        let earnedAchievements = evaluateMilestones(
            for: workout, weeklyGoal: weeklyGoal, calendar: calendar, unit: unit
        )
        // Backfilled/past-dated workouts still earn milestones (persisted above) but never
        // celebrate — the summary card only shows the ones worth celebrating right now.
        let achievements = Milestones.isCelebrationWorthy(workoutDate: workout.startedAt, now: now)
            ? earnedAchievements : []
        save()
        onWorkoutFinished?(workout)
        workoutFinishedObservers.forEach { $0(workout) }
        WidgetSnapshotWriter.refresh(store: self)
        return summary(for: workout, session: session, prs: prs, achievements: achievements)
    }

    /// History only ever holds what was actually done: an unticked planned row, and an exercise
    /// left with no rows, are dropped here — in `finish`, not `sync`, so an in-progress session
    /// keeps its planned rows for resume. The `WorkoutModel` itself stays even when it empties.
    ///
    /// A pruned exercise's *note* survives onto the workout's own notes. "Skipped, left shoulder
    /// pinching" is exactly the note worth keeping, and it was thrown away with the row.
    private func pruneUnfinishedRows(of workout: WorkoutModel) {
        for exerciseModel in workout.exercises ?? [] {
            for setModel in (exerciseModel.sets ?? []).filter({ !$0.isCompleted }) {
                context.delete(setModel)
            }
        }
        let emptied = (workout.exercises ?? []).filter { ($0.sets ?? []).allSatisfy { !$0.isCompleted } }
        let rescued = emptied.compactMap { exerciseModel -> String? in
            let note = exerciseModel.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return nil }
            let name = exerciseModel.exercise?.name ?? "Exercise"
            return "Skipped \(name): \(note)"
        }
        if !rescued.isEmpty {
            workout.notes = ([workout.notes] + rescued)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        // Deleted through the context alone: re-assigning the parent's array while SwiftData is
        // mid-way through updating that same relationship traps.
        emptied.forEach(context.delete)
    }

    private func summary(
        for workout: WorkoutModel, session: WorkoutSession, prs: [PersonalRecordInfo],
        achievements: [AchievementInfo]
    ) -> WorkoutSummary {
        let endedAt = workout.endedAt ?? Date()
        // Working sets only, the same count the History row and the weekly recap show.
        let setsDone = session.exercises.flatMap(\.sets)
            .filter { $0.isDone && $0.kind.countsTowardStats }.count
        let previous = previousWorkout(before: workout)
        return WorkoutSummary(
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(workout.startedAt))),
            volumeKg: session.volumeKg, setsDone: setsDone, prs: prs, musclesHit: session.musclesHit,
            achievements: achievements, previous: previous.map(previousWorkoutSummary),
            e1rmChanges: e1rmChanges(session: session, previous: previous),
            distanceMeters: session.distanceMeters
        )
    }

    /// The latest finished workout on the same routine — same title when neither has a routine
    /// — started before this one. "Before its own date", not "newest overall", so a backfill
    /// compares against what came before it.
    private func previousWorkout(before workout: WorkoutModel) -> WorkoutModel? {
        finishedWorkoutModelsNewestFirst().first { candidate in
            guard candidate.id != workout.id, candidate.startedAt < workout.startedAt else { return false }
            if let routineID = workout.routineID { return candidate.routineID == routineID }
            return candidate.routineID == nil && candidate.title == workout.title
        }
    }

    private func previousWorkoutSummary(_ workout: WorkoutModel) -> PreviousWorkoutSummary {
        let sets = (workout.exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
        let endedAt = workout.endedAt ?? workout.startedAt
        return PreviousWorkoutSummary(
            workoutID: workout.id, date: workout.startedAt, volumeKg: workoutVolume(workout),
            setsDone: sets.count,
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(workout.startedAt))),
            prCount: prCount(for: workout.id)
        )
    }

    /// One row per exercise, merging every entry for it in the session.
    ///
    /// The same exercise can legitimately appear twice in one workout — bench 80 × 8 early, bench
    /// again at 100 × 3 at the end. A `seen` guard emitted the first entry and dropped the second
    /// entry's sets entirely, so the summary reported the 80 × 8 as the session's best while the
    /// PR banner right above it celebrated the 100 × 3.
    private func e1rmChanges(session: WorkoutSession, previous: WorkoutModel?) -> [ExerciseE1RMChange] {
        var order: [UUID] = []
        var setsByExercise: [UUID: [SetEntry]] = [:]
        var names: [UUID: String] = [:]
        for entry in session.exercises {
            if setsByExercise[entry.exercise.id] == nil {
                order.append(entry.exercise.id)
                names[entry.exercise.id] = entry.exercise.name
            }
            setsByExercise[entry.exercise.id, default: []] += entry.sets
        }
        return order.compactMap { exerciseID in
            let current = (setsByExercise[exerciseID] ?? [])
                .filter { $0.isDone && $0.kind.countsTowardStats }
                .compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }
                .max()
            let before = previous.flatMap { bestE1RM(exerciseID: exerciseID, in: $0) }
            guard current != nil || before != nil else { return nil }
            return ExerciseE1RMChange(
                exerciseID: exerciseID, name: names[exerciseID] ?? "", previous: before, current: current
            )
        }
    }

    /// In-progress (never finished, never discarded) workouts, newest first — what a crash or
    /// force-quit mid-session leaves behind. The launch flow offers to resume the newest via
    /// `resumeSession(for:)` and purges the rest with `purgeUnfinished(olderThan:)`.
    func unfinishedWorkouts() -> [WorkoutModel] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt == nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return fetch(descriptor)
    }

    /// Clears out unfinished workouts started before `date`, **without ever destroying logged
    /// work**. Returns how many were dealt with.
    ///
    /// This runs at launch, before the user is asked anything. It used to delete outright, so a
    /// Friday session with 14 sets in it was silently gone by Sunday — no prompt, no undo — and
    /// on a CloudKit-mirrored store it could delete a workout another device was still logging.
    /// A workout with completed sets is now auto-finished instead, at its own last logged set
    /// (see `endDate(for:session:now:)`), which is what the lifter would have got had they
    /// remembered to tap Finish. Only a genuinely empty shell is deleted.
    @discardableResult
    func purgeUnfinished(olderThan date: Date) -> Int {
        let stale = unfinishedWorkouts().filter { $0.startedAt < date }
        guard !stale.isEmpty else { return 0 }
        for workout in stale {
            let hasLoggedWork = (workout.exercises ?? [])
                .flatMap { $0.sets ?? [] }
                .contains(where: \.isCompleted)
            if hasLoggedWork, let session = resumeSession(for: workout.id) {
                _ = finish(session: session)
            } else {
                context.delete(workout)
            }
        }
        save()
        return stale.count
    }

    /// Re-opens an unfinished workout as a live `WorkoutSession` so `ActiveWorkoutView` can carry
    /// on where it stopped. Nil once the workout has been finished or deleted.
    ///
    /// Everything the session carries that `sync` does not persist is rebuilt here, because a
    /// resumed workout is meant to be indistinguishable from the one that was interrupted: the
    /// history strip and sparkline, the per-set ghost of the previous session (`withGhosts`), and
    /// the "already logged once" set of ids that stops a re-tick restarting rest
    /// (`markLoggedSetsAsSeen`). The "why" headline comes back from the per-set
    /// `prescriptionReason` the store *does* persist (see `WorkoutExerciseEntry.init(model:)`),
    /// and a timed hold's target from its uncompleted row's duration.
    func resumeSession(for workoutID: UUID) -> WorkoutSession? {
        guard let model = fetchWorkoutModel(id: workoutID), model.endedAt == nil else { return nil }
        // Fetched once and shared: every exercise's `exerciseInfo` stats and history strip would
        // otherwise re-query the finished-workout list, the PR cache and its own `ExerciseModel`.
        let facts = makeSessionFacts(routineID: model.routineID)
        let session = WorkoutSession(model: model, exerciseInfo: { self.exerciseInfo(for: $0, facts: facts) })
        session.exercises = session.exercises.map {
            withGhosts(withHistoryStrip($0, facts: facts), facts: facts)
        }
        session.routineGlyphs = routineGlyphs(for: session.exercises)
        session.markLoggedSetsAsSeen()
        return session
    }

    /// Everything finished, newest first: the main store's own workouts plus whatever was
    /// imported from Apple Health, which lives in the separate always-local Health store (see
    /// `WorkoutStore+HealthImport.swift`). Merged here so History stays one list and no caller
    /// has to know where a row came from.
    func history() -> [WorkoutRecord] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let models = fetch(descriptor)
        let own = models.map { WorkoutRecord(model: $0, prCount: prCount(for: $0.id)) }
        let imported = importedHealthWorkouts().map(Self.record(imported:))
        return (own + imported).sorted { $0.date > $1.date }
    }

    func workout(id: UUID) -> WorkoutModel? {
        fetchWorkoutModel(id: id)
    }

    /// Deletes a workout and its sets, then rebuilds the PR cache and event log from what
    /// remains — so a mis-typed record dies with the workout that set it. Returns a snapshot
    /// that `restoreWorkout(_:)` re-inserts with the same ids, for an undo toast.
    @discardableResult
    func deleteWorkout(id: UUID) -> DeletedWorkout? {
        guard let model = fetchWorkoutModel(id: id) else {
            // Not in the main store: it may be an Apple Health import, which lives in the local
            // Health store and leaves a tombstone behind so it is never re-imported.
            return deleteImportedHealthWorkout(id: id).map(DeletedWorkout.init(imported:))
        }
        var snapshot = DeletedWorkout(model: model)
        let wasFinished = model.endedAt != nil
        // Captured before the delete: the routine slots whose engine memory this workout fed,
        // and the milestone tiers it earned.
        let slots = Self.progressionSlots(of: model)
        snapshot.achievements = achievementModels(forWorkoutID: id).map(DeletedWorkout.Achievement.init)
        // A workout DaGym wrote to Apple Health should not outlive itself there.
        if let healthKitID = model.healthKitID {
            onWorkoutDeletedFromHealth?(healthKitID)
        }
        // A mistyped session that earned a badge left it earned for ever — and `earnedTiers`
        // then blocked the lifter from earning that same tier legitimately later.
        achievementModels(forWorkoutID: id).forEach(context.delete)
        context.delete(model)
        save()
        if wasFinished {
            rebuildPersonalRecords()
            replayProgression(slots: slots)
            save()
        }
        return snapshot
    }

    /// The `(routine, exercise)` pairs a workout's rows were logged under — the routine slots
    /// whose `stallJSON`/`trainingMaxKg` this workout's judgement was folded into.
    private static func progressionSlots(of workout: WorkoutModel) -> [ProgressionSlot] {
        (workout.exercises ?? []).compactMap { exerciseModel in
            guard !exerciseModel.excludedFromProgression,
                  let routineID = exerciseModel.routineID ?? workout.routineID,
                  let exerciseID = exerciseModel.exercise?.id else { return nil }
            return ProgressionSlot(routineID: routineID, exerciseID: exerciseID)
        }
    }

    /// Re-derives each slot's engine memory from the history that is actually there now.
    ///
    /// Deleting a workout reverted its PRs but not its stall state, so a session deleted because
    /// it was mistyped left `consecutiveMisses` elevated and the *next* session could be deloaded
    /// on evidence the lifter had removed. The state is a fold over history, so the only honest
    /// way back is to fold it again: replay the judgement `finish` makes, session by session,
    /// over what remains. `restoreWorkout` runs the same replay, which is what makes undo exact.
    ///
    /// The training max and its cycle marker are carried over rather than replayed — the lifter
    /// set the TM, and the engine only bumps it once per cycle, so re-deriving it would either
    /// lose it or bump it twice.
    private func replayProgression(slots: [ProgressionSlot]) {
        let all = finishedWorkoutModelsNewestFirst()
        for slot in Set(slots) {
            guard let routine = fetchRoutineModel(id: slot.routineID),
                  let routineExercise = (routine.exercises ?? [])
                      .first(where: { $0.exercise?.id == slot.exerciseID }),
                  let exerciseModel = routineExercise.exercise,
                  let plannedSets = routineExercise.plannedSets else { continue }
            var facts = makeSessionFacts(routineID: routine.id)
            let info = exerciseInfo(for: exerciseModel, facts: facts)
            let judged = all.indices.filter { Self.isJudged(all[$0], exerciseID: slot.exerciseID) }
            var state = StallState(trainingMaxCycle: routineExercise.stallStateValue.trainingMaxCycle)
            // Oldest first, and only as far back as the engine's own history window reaches.
            for index in judged.prefix(Self.progressionReplayLimit).reversed() {
                routineExercise.stallStateValue = state
                // Exactly what `finish` sees: this session is still *outside* its own baseline.
                facts.finishedWorkouts = Array(all.dropFirst(index + 1))
                guard let result = computeProgression(
                    routine: routine, routineExercise: routineExercise, exerciseInfo: info,
                    plannedSets: plannedSets, facts: facts
                ) else { break }
                state = result.stall
            }
            routineExercise.stallStateValue = state
        }
    }

    /// Whether this workout's row for `exerciseID` is one the engine would ever judge — the same
    /// test `exerciseHistory` and `persistProgression` apply.
    private static func isJudged(_ workout: WorkoutModel, exerciseID: UUID) -> Bool {
        guard let match = (workout.exercises ?? []).first(where: { $0.exercise?.id == exerciseID })
        else { return false }
        return !match.excludedFromProgression && !match.wasPlannedDeload
            && (match.sets ?? []).contains(where: \.isCompleted)
    }

    /// Matches `exerciseHistory`'s own `limit`: further back than this the engine cannot see, so
    /// replaying further cannot change the answer.
    private static let progressionReplayLimit = 6

    private func achievementModels(forWorkoutID id: UUID) -> [AchievementModel] {
        let predicate = #Predicate<AchievementModel> { $0.workoutID == id }
        return fetch(FetchDescriptor(predicate: predicate))
    }

    /// Puts a deleted workout back exactly as it was (same ids, sets and flags) and rebuilds
    /// the PR cache. A no-op if a workout with that id already exists again.
    func restoreWorkout(_ snapshot: DeletedWorkout) {
        if let imported = snapshot.importedHealthWorkout {
            restoreImportedHealthWorkout(imported)
            return
        }
        guard fetchWorkoutModel(id: snapshot.id) == nil else { return }
        let workout = WorkoutModel(
            id: snapshot.id, title: snapshot.title, startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt, notes: snapshot.notes, isBackfilled: snapshot.isBackfilled,
            routineID: snapshot.routineID, routineName: snapshot.routineName,
            bodyweightKg: snapshot.bodyweightKg, sourceDevice: snapshot.sourceDevice,
            // Deliberately not `snapshot.healthKitID`: deleting the workout also deleted the
            // `HKWorkout` DaGym had written for it, so the restored workout has nothing in Health
            // yet. Clearing it lets the finished-workout hook below write a fresh one.
            healthKitID: nil
        )
        context.insert(workout)
        // Children are linked through the `workout:`/`workoutExercise:` inverses only — assigning
        // the parent's array at the same time makes SwiftData rebuild a relationship it is already
        // mid-way through updating, which traps.
        for exercise in snapshot.exercises {
            let exerciseModel = WorkoutExerciseModel(
                id: exercise.id, order: exercise.order, supersetGroup: exercise.supersetGroup,
                note: exercise.note, wasSubstitution: exercise.wasSubstitution,
                wasPlannedDeload: exercise.wasPlannedDeload,
                excludedFromProgression: exercise.excludedFromProgression, routineID: exercise.routineID,
                exercise: exercise.exerciseID.flatMap(fetchExerciseModel), workout: workout
            )
            context.insert(exerciseModel)
            for set in exercise.sets {
                let setModel = SetLogModel(
                    id: set.id, order: set.order, kind: set.kind, weightKg: set.weightKg, reps: set.reps,
                    durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters,
                    inclinePercent: set.inclinePercent, assistanceKg: set.assistanceKg, rpe: set.rpe,
                    isCompleted: set.isCompleted, completedAt: set.completedAt,
                    prescriptionReason: set.prescriptionReason, workoutExercise: exerciseModel
                )
                context.insert(setModel)
            }
        }
        for achievement in snapshot.achievements {
            context.insert(AchievementModel(
                id: achievement.id, milestoneID: achievement.milestoneID, tier: achievement.tier,
                earnedAt: achievement.earnedAt, workoutID: snapshot.id
            ))
        }
        save()
        if snapshot.endedAt != nil {
            rebuildPersonalRecords()
            // The delete replayed this workout out of the engine's memory; put it back the same
            // way, so undo restores the stall state as exactly as it restores the sets.
            replayProgression(slots: Self.progressionSlots(of: workout))
            save()
        }
        // Re-write it to Apple Health if it had been written before (and the toggle is still on):
        // the delete above removed our own `HKWorkout`, so undo has to put that back too.
        if snapshot.healthKitID != nil, snapshot.endedAt != nil {
            onWorkoutFinished?(workout)
        }
    }

    /// Total finished-workout count and lifetime volume, for the History header.
    func lifetimeStats() -> (workouts: Int, volumeKg: Double) {
        let finished = finishedWorkoutModelsNewestFirst()
        let volume = finished.reduce(0.0) { total, workout in
            total + workoutVolume(workout)
        }
        // Imported Apple Health sessions count as workouts done; they carry no volume.
        return (finished.count + importedHealthWorkouts().count, volume)
    }

    /// Full read-only detail for a finished workout, for `WorkoutDetailView`.
    /// Returns an empty placeholder if the workout can't be found.
    func workoutDetail(id: UUID) -> WorkoutDetail {
        guard let model = fetchWorkoutModel(id: id) else {
            // Imported Apple Health sessions live in the local Health store and carry no sets.
            if let imported = importedHealthWorkout(id: id) {
                return WorkoutDetail(
                    id: imported.id, title: imported.title, startedAt: imported.startedAt,
                    endedAt: imported.endedAt, isBackfilled: true
                )
            }
            return WorkoutDetail(title: "", startedAt: Date())
        }
        let entries = (model.exercises ?? []).sorted { $0.order < $1.order }.map { exerciseModel in
            let info = exerciseModel.exercise.map { exerciseInfo(for: $0) }
                ?? ExerciseInfo(name: "Deleted exercise", primary: [], equipment: "other")
            return WorkoutExerciseEntry(model: exerciseModel, exercise: info)
        }
        return WorkoutDetail(
            id: model.id, title: model.title, startedAt: model.startedAt, endedAt: model.endedAt,
            exercises: entries, notes: model.notes, isBackfilled: model.isBackfilled,
            prCount: prCount(for: model.id), routineGlyphs: routineGlyphs(for: entries)
        )
    }

    /// "80 × 8,8,7" style lines for the last few finished sessions of an exercise — "0:45, 0:40"
    /// for a timed hold, "12, 12, 10" for unloaded reps (see `sessionLine`). Pass
    /// `finishedWorkouts` (newest first) to reuse an already-fetched list instead of querying
    /// the store again.
    /// `style`, when passed, is used as-is instead of re-fetching the `ExerciseModel` just to
    /// read it — a caller holding the `ExerciseInfo` already has it (`ExerciseInfo.loggingStyle`
    /// *is* `ExerciseModel.style`; the `.weightReps` default matches the deleted-exercise case).
    func lastSessions(
        exerciseID: UUID, limit: Int = 3, finishedWorkouts: [WorkoutModel]? = nil,
        style: ExerciseInfo.LoggingStyle? = nil
    ) -> [String] {
        let style = style ?? fetchExerciseModel(id: exerciseID)?.style ?? .weightReps
        var lines: [String] = []
        for workout in finishedWorkouts ?? finishedWorkoutModelsNewestFirst() {
            guard let line = sessionLine(exerciseID: exerciseID, style: style, in: workout) else { continue }
            lines.append(line)
            if lines.count == limit { break }
        }
        return lines
    }

    /// e1RM per finished workout that included this exercise, oldest first, for the sparkline.
    /// Pass `finishedWorkouts` (newest first) to reuse an already-fetched list.
    func e1rmSeries(exerciseID: UUID, finishedWorkouts: [WorkoutModel]? = nil) -> [(Date, Double)] {
        (finishedWorkouts ?? finishedWorkoutModelsNewestFirst()).reversed().compactMap { workout in
            bestE1RM(exerciseID: exerciseID, in: workout).map { (workout.startedAt, $0) }
        }
    }

    /// The card sparkline's per-session value, oldest first, by how the exercise is logged:
    /// best hold for a timed exercise, best reps for unloaded reps, else best e1RM. Pass
    /// `finishedWorkouts` (newest first) to reuse an already-fetched list, and `style` to skip
    /// the `ExerciseModel` fetch that only reads it (see `lastSessions`).
    func sparklineSeries(
        exerciseID: UUID, finishedWorkouts: [WorkoutModel]? = nil,
        style: ExerciseInfo.LoggingStyle? = nil
    ) -> [(Date, Double)] {
        let best: ((SetLogModel) -> Double)?
        switch style ?? fetchExerciseModel(id: exerciseID)?.style ?? .weightReps {
        case .timedHold: best = { Double($0.durationSeconds ?? 0) }
        case .cardio: best = cardioSparklineValue(exerciseID: exerciseID, finishedWorkouts: finishedWorkouts)
        case .bodyweightReps: best = { Double($0.reps) }
        case .weightReps, .assisted, .weightedBodyweight: best = nil
        }
        guard let best else {
            return e1rmSeries(exerciseID: exerciseID, finishedWorkouts: finishedWorkouts)
        }
        return bestPerSession(exerciseID: exerciseID, finishedWorkouts: finishedWorkouts, value: best)
    }

    private func bestPerSession(
        exerciseID: UUID, finishedWorkouts: [WorkoutModel]? = nil, value: (SetLogModel) -> Double
    ) -> [(Date, Double)] {
        (finishedWorkouts ?? finishedWorkoutModelsNewestFirst()).reversed().compactMap { workout in
            guard let match = matchingSets(exerciseID: exerciseID, in: workout) else { return nil }
            let best = match
                .filter { $0.isCompleted && $0.setKind.countsTowardStats }
                .map(value).max()
            return best.map { (workout.startedAt, $0) }
        }
    }

    /// Every finished workout's start date, for `Streaks.weekly` — imported Apple Health
    /// sessions included, since a session logged on the Watch still broke the rest day.
    func workoutDates() -> [Date] {
        finishedWorkoutModelsNewestFirst().map(\.startedAt)
            + importedHealthWorkouts().map(\.startedAt)
    }

    /// Recovery stimulus events (`GymCore.Recovery`) from completed, non-warm-up sets of
    /// finished workouts started on or after `since`. Primary movers get a full share, secondary
    /// movers half; effort comes from the set's RPE, mapped to an RIR-based factor.
    func recoveryEvents(since: Date) -> [StimulusEvent] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil && $0.startedAt >= since }
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: predicate)
        let workouts = fetch(descriptor)
        return workouts.flatMap(recoveryEvents(in:))
    }

    // MARK: - Helpers

    /// Weight × reps over counting sets, reading each row's **lifted** load — an assisted row's
    /// logged weight is the machine's help, not load, so it adds nothing. One expression, shared
    /// with the History rows, the weekly recap and the Health write: see `WorkoutModel
    /// .loadedVolumeKg`.
    private func workoutVolume(_ workout: WorkoutModel) -> Double {
        workout.loadedVolumeKg
    }

    private func sessionLine(
        exerciseID: UUID, style: ExerciseInfo.LoggingStyle, in workout: WorkoutModel
    ) -> String? {
        guard let match = matchingSets(exerciseID: exerciseID, in: workout) else { return nil }
        let sets = match.filter { $0.isCompleted && $0.setKind.countsTowardStats }
        guard let first = sets.first else { return nil }
        switch style {
        case .timedHold:
            return sets.map { WorkoutSession.clock($0.durationSeconds ?? 0) }.joined(separator: ", ")
        case .cardio:
            return cardioSessionLine(sets: sets, unit: preferredDistanceUnit)
        case .bodyweightReps:
            return sets.map { String($0.reps) }.joined(separator: ", ")
        case .weightReps, .assisted, .weightedBodyweight:
            let reps = sets.map { String($0.reps) }.joined(separator: ",")
            return "\(WorkoutSession.format(first.weightKg)) × \(reps)"
        }
    }

    private func bestE1RM(exerciseID: UUID, in workout: WorkoutModel) -> Double? {
        guard let match = matchingSets(exerciseID: exerciseID, in: workout) else { return nil }
        return match
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }
            .max()
    }

    /// Every logged row for `exerciseID` in this workout, in logged order — nil when the workout
    /// doesn't contain the exercise at all.
    ///
    /// It used to take `.first`, so an exercise logged twice in one session (bench 80 × 8 early,
    /// bench 100 × 3 at the end) was half-invisible: the history line, the card sparkline and
    /// the exercise's best-e1RM all read the first entry and never saw the heavier one.
    func matchingSets(exerciseID: UUID, in workout: WorkoutModel) -> [SetLogModel]? {
        let matches = (workout.exercises ?? [])
            .filter { $0.exercise?.id == exerciseID }
            .sorted { $0.order < $1.order }
        guard !matches.isEmpty else { return nil }
        return matches.flatMap { ($0.sets ?? []).sorted { $0.order < $1.order } }
    }
}
