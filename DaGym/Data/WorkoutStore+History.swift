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
        // A live session is finished exactly once: a second call (double-tap, re-entrant sheet)
        // would otherwise re-run progression with this session now inside its own baseline and
        // burn a second stall. Backfills carry their end date from `startBackfill`, so they are
        // recognised by `isBackfilled` rather than by a nil `endedAt`.
        if workout.endedAt != nil, !workout.isBackfilled {
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
        // A backfilled workout keeps the `date + duration` end it was started with; only a live
        // session ends now.
        let endedAt = workout.isBackfilled ? (workout.endedAt ?? now) : now
        workout.endedAt = endedAt
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
    private func pruneUnfinishedRows(of workout: WorkoutModel) {
        for exerciseModel in workout.exercises ?? [] {
            for setModel in (exerciseModel.sets ?? []).filter({ !$0.isCompleted }) {
                context.delete(setModel)
            }
            exerciseModel.sets = (exerciseModel.sets ?? []).filter(\.isCompleted)
        }
        let emptied = (workout.exercises ?? []).filter { ($0.sets ?? []).isEmpty }
        emptied.forEach(context.delete)
        workout.exercises = (workout.exercises ?? []).filter { !($0.sets ?? []).isEmpty }
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
            e1rmChanges: e1rmChanges(session: session, previous: previous)
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

    private func e1rmChanges(session: WorkoutSession, previous: WorkoutModel?) -> [ExerciseE1RMChange] {
        var seen = Set<UUID>()
        return session.exercises.compactMap { entry in
            guard seen.insert(entry.exercise.id).inserted else { return nil }
            let current = entry.sets
                .filter { $0.isDone && $0.kind.countsTowardStats }
                .compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }
                .max()
            let before = previous.flatMap { bestE1RM(exerciseID: entry.exercise.id, in: $0) }
            guard current != nil || before != nil else { return nil }
            return ExerciseE1RMChange(
                exerciseID: entry.exercise.id, name: entry.exercise.name, previous: before, current: current
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

    /// Deletes every unfinished workout started before `date` (and, by cascade, its sets).
    /// Returns how many were removed.
    @discardableResult
    func purgeUnfinished(olderThan date: Date) -> Int {
        let stale = unfinishedWorkouts().filter { $0.startedAt < date }
        guard !stale.isEmpty else { return 0 }
        stale.forEach(context.delete)
        save()
        return stale.count
    }

    /// Re-opens an unfinished workout as a live `WorkoutSession` (its sets, done flags, notes and
    /// per-exercise history strip restored) so `ActiveWorkoutView` can carry on where it stopped.
    /// Nil once the workout has been finished or deleted.
    func resumeSession(for workoutID: UUID) -> WorkoutSession? {
        guard let model = fetchWorkoutModel(id: workoutID), model.endedAt == nil else { return nil }
        // Fetched once and shared: every exercise's `exerciseInfo` stats and history strip would
        // otherwise re-query the finished-workout list, the PR cache and its own `ExerciseModel`.
        let facts = makeSessionFacts(routineID: model.routineID)
        let session = WorkoutSession(model: model, exerciseInfo: { self.exerciseInfo(for: $0, facts: facts) })
        session.exercises = session.exercises.map { withHistoryStrip($0, facts: facts) }
        session.routineGlyphs = routineGlyphs(for: session.exercises)
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
        let snapshot = DeletedWorkout(model: model)
        let wasFinished = model.endedAt != nil
        // A workout DaGym wrote to Apple Health should not outlive itself there.
        if let healthKitID = model.healthKitID {
            onWorkoutDeletedFromHealth?(healthKitID)
        }
        context.delete(model)
        save()
        if wasFinished { rebuildPersonalRecords() }
        return snapshot
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
                    assistanceKg: set.assistanceKg, rpe: set.rpe, isCompleted: set.isCompleted,
                    completedAt: set.completedAt, prescriptionReason: set.prescriptionReason,
                    workoutExercise: exerciseModel
                )
                context.insert(setModel)
            }
        }
        save()
        if snapshot.endedAt != nil { rebuildPersonalRecords() }
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
        case .timedHold, .cardio: best = { Double($0.durationSeconds ?? 0) }
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
            guard let match = matchingExercise(exerciseID: exerciseID, in: workout) else { return nil }
            let best = (match.sets ?? [])
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

    private func recoveryEvents(in workout: WorkoutModel) -> [StimulusEvent] {
        (workout.exercises ?? []).flatMap { exerciseModel -> [StimulusEvent] in
            guard let exercise = exerciseModel.exercise else { return [] }
            let fallbackDate = workout.startedAt
            return (exerciseModel.sets ?? [])
                .filter { $0.isCompleted && $0.setKind.countsTowardStats }
                .flatMap { stimulusEvents(for: $0, exercise: exercise, fallbackDate: fallbackDate) }
        }
    }

    private func stimulusEvents(
        for setLog: SetLogModel, exercise: ExerciseModel, fallbackDate: Date
    ) -> [StimulusEvent] {
        let date = setLog.completedAt ?? fallbackDate
        let effort = Self.effortFactor(rpe: setLog.rpe)
        let primary = exercise.primary.map { muscle in
            StimulusEvent(muscle: muscle, share: 1.0, effort: effort, date: date)
        }
        let secondary = exercise.secondary.map { muscle in
            StimulusEvent(muscle: muscle, share: 0.5, effort: effort, date: date)
        }
        return primary + secondary
    }

    /// RIR 0 → 1.0, RIR ≥ 4 → 0.5 (linear in between), unknown RPE → 0.75 (§7 of the plan).
    private static func effortFactor(rpe: Double?) -> Double {
        guard let rpe else { return 0.75 }
        let rir = Effort(rpe: rpe).rir
        guard rir > 0 else { return 1.0 }
        guard rir < 4 else { return 0.5 }
        return 1.0 - Double(rir) * 0.125
    }

    private func workoutVolume(_ workout: WorkoutModel) -> Double {
        (workout.exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    }

    private func sessionLine(
        exerciseID: UUID, style: ExerciseInfo.LoggingStyle, in workout: WorkoutModel
    ) -> String? {
        guard let match = matchingExercise(exerciseID: exerciseID, in: workout) else { return nil }
        let sets = (match.sets ?? [])
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .sorted { $0.order < $1.order }
        guard let first = sets.first else { return nil }
        switch style {
        case .timedHold, .cardio:
            return sets.map { WorkoutSession.clock($0.durationSeconds ?? 0) }.joined(separator: ", ")
        case .bodyweightReps:
            return sets.map { String($0.reps) }.joined(separator: ", ")
        case .weightReps, .assisted, .weightedBodyweight:
            let reps = sets.map { String($0.reps) }.joined(separator: ",")
            return "\(WorkoutSession.format(first.weightKg)) × \(reps)"
        }
    }

    private func bestE1RM(exerciseID: UUID, in workout: WorkoutModel) -> Double? {
        guard let match = matchingExercise(exerciseID: exerciseID, in: workout) else { return nil }
        return (match.sets ?? [])
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .compactMap { OneRepMax.estimate(weight: $0.weightKg, reps: $0.reps) }
            .max()
    }

    private func matchingExercise(exerciseID: UUID, in workout: WorkoutModel) -> WorkoutExerciseModel? {
        (workout.exercises ?? []).first { $0.exercise?.id == exerciseID }
    }
}

/// A value copy of a deleted workout's whole graph, enough to re-insert it unchanged.
/// Handed back by `WorkoutStore.deleteWorkout(id:)` so an undo toast can call
/// `restoreWorkout(_:)`; nothing is kept in the store, so it's CloudKit-neutral.
struct DeletedWorkout: Sendable {
    struct Exercise: Sendable {
        var id: UUID
        var order: Int
        var supersetGroup: Int?
        var note: String
        var wasSubstitution: Bool
        var wasPlannedDeload: Bool
        var excludedFromProgression: Bool
        var routineID: UUID?
        var exerciseID: UUID?
        var sets: [SetLog]
    }

    struct SetLog: Sendable {
        var id: UUID
        var order: Int
        var kind: String
        var weightKg: Double
        var reps: Int
        var durationSeconds: Int?
        var distanceMeters: Double?
        var assistanceKg: Double?
        var rpe: Double?
        var isCompleted: Bool
        var completedAt: Date?
        var prescriptionReason: String
    }

    var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var notes: String
    var isBackfilled: Bool
    var routineID: UUID?
    var routineName: String
    var bodyweightKg: Double?
    var sourceDevice: String
    var healthKitID: String?
    var exercises: [Exercise]
    /// Set only when the deleted row was an Apple Health import (which lives in the local Health
    /// store, not the main one) — `restoreWorkout(_:)` routes on it.
    var importedHealthWorkout: ImportedHealthWorkoutSnapshot?

    init(model: WorkoutModel) {
        importedHealthWorkout = nil
        id = model.id
        title = model.title
        startedAt = model.startedAt
        endedAt = model.endedAt
        notes = model.notes
        isBackfilled = model.isBackfilled
        routineID = model.routineID
        routineName = model.routineName
        bodyweightKg = model.bodyweightKg
        sourceDevice = model.sourceDevice
        healthKitID = model.healthKitID
        exercises = (model.exercises ?? []).sorted { $0.order < $1.order }.map { exercise in
            Exercise(
                id: exercise.id, order: exercise.order, supersetGroup: exercise.supersetGroup,
                note: exercise.note, wasSubstitution: exercise.wasSubstitution,
                wasPlannedDeload: exercise.wasPlannedDeload,
                excludedFromProgression: exercise.excludedFromProgression,
                routineID: exercise.routineID,
                exerciseID: exercise.exercise?.id,
                sets: (exercise.sets ?? []).sorted { $0.order < $1.order }.map { set in
                    SetLog(
                        id: set.id, order: set.order, kind: set.kind, weightKg: set.weightKg,
                        reps: set.reps, durationSeconds: set.durationSeconds,
                        distanceMeters: set.distanceMeters, assistanceKg: set.assistanceKg, rpe: set.rpe,
                        isCompleted: set.isCompleted, completedAt: set.completedAt,
                        prescriptionReason: set.prescriptionReason
                    )
                }
            )
        }
    }
}
