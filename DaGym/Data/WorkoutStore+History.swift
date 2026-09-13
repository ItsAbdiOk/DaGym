import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// Ends the session, computes PRs against the cache and returns a summary. Backfilled or
    /// otherwise earlier-dated workouts never claim a PR against a later-dated one.
    /// `weeklyGoal` (`Preferences.weeklyGoal`) feeds the streak/consistency milestones; it's
    /// additive with a default so existing call sites compile unchanged.
    func finish(session: WorkoutSession, weeklyGoal: Int = 4) -> WorkoutSummary {
        sync(session: session)
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID) else {
            return WorkoutSummary(durationSeconds: 0, volumeKg: 0, setsDone: 0, prs: [], musclesHit: [:])
        }
        let endedAt = Date()
        workout.endedAt = endedAt
        let prs = evaluatePRs(session: session, workout: workout)
        let earnedAchievements = evaluateMilestones(for: workout, weeklyGoal: weeklyGoal)
        // Backfilled/past-dated workouts still earn milestones (persisted above) but never
        // celebrate — the summary card only shows the ones worth celebrating right now.
        let achievements = Milestones.isCelebrationWorthy(workoutDate: workout.startedAt, now: endedAt)
            ? earnedAchievements : []
        save()
        onWorkoutFinished?(workout)
        workoutFinishedObservers.forEach { $0(workout) }
        WidgetSnapshotWriter.refresh(store: self)
        return WorkoutSummary(
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(workout.startedAt))),
            volumeKg: session.volumeKg, setsDone: session.setsDone, prs: prs, musclesHit: session.musclesHit,
            achievements: achievements
        )
    }

    func history() -> [WorkoutRecord] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map { WorkoutRecord(model: $0, prCount: prCount(for: $0.id)) }
    }

    func workout(id: UUID) -> WorkoutModel? {
        fetchWorkoutModel(id: id)
    }

    func deleteWorkout(id: UUID) {
        guard let model = fetchWorkoutModel(id: id) else { return }
        context.delete(model)
        save()
    }

    /// Total finished-workout count and lifetime volume, for the History header.
    func lifetimeStats() -> (workouts: Int, volumeKg: Double) {
        let finished = finishedWorkoutsNewestFirst()
        let volume = finished.reduce(0.0) { total, workout in
            total + workoutVolume(workout)
        }
        return (finished.count, volume)
    }

    /// Full read-only detail for a finished workout, for `WorkoutDetailView`.
    /// Returns an empty placeholder if the workout can't be found.
    func workoutDetail(id: UUID) -> WorkoutDetail {
        guard let model = fetchWorkoutModel(id: id) else {
            return WorkoutDetail(title: "", startedAt: Date())
        }
        let entries = (model.exercises ?? []).sorted { $0.order < $1.order }.map { exerciseModel in
            let info = exerciseModel.exercise.map(exerciseInfo(for:))
                ?? ExerciseInfo(name: "Deleted exercise", primary: [], equipment: "other")
            return WorkoutExerciseEntry(model: exerciseModel, exercise: info)
        }
        return WorkoutDetail(
            id: model.id, title: model.title, startedAt: model.startedAt, endedAt: model.endedAt,
            exercises: entries, notes: model.notes, isBackfilled: model.isBackfilled,
            prCount: prCount(for: model.id)
        )
    }

    /// "80 × 8,8,7" style lines for the last few finished sessions of an exercise.
    func lastSessions(exerciseID: UUID, limit: Int = 3) -> [String] {
        var lines: [String] = []
        for workout in finishedWorkoutsNewestFirst() {
            guard let line = sessionLine(exerciseID: exerciseID, in: workout) else { continue }
            lines.append(line)
            if lines.count == limit { break }
        }
        return lines
    }

    /// e1RM per finished workout that included this exercise, oldest first, for the sparkline.
    func e1rmSeries(exerciseID: UUID) -> [(Date, Double)] {
        finishedWorkoutsNewestFirst().reversed().compactMap { workout in
            bestE1RM(exerciseID: exerciseID, in: workout).map { (workout.startedAt, $0) }
        }
    }

    /// Every finished workout's start date, for `Streaks.weekly`.
    func workoutDates() -> [Date] {
        finishedWorkoutsNewestFirst().map(\.startedAt)
    }

    /// Recovery stimulus events (`GymCore.Recovery`) from completed, non-warm-up sets of
    /// finished workouts started on or after `since`. Primary movers get a full share, secondary
    /// movers half; effort comes from the set's RPE, mapped to an RIR-based factor.
    func recoveryEvents(since: Date) -> [StimulusEvent] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil && $0.startedAt >= since }
        let descriptor = FetchDescriptor<WorkoutModel>(predicate: predicate)
        let workouts = (try? context.fetch(descriptor)) ?? []
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

    private func finishedWorkoutsNewestFirst() -> [WorkoutModel] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func workoutVolume(_ workout: WorkoutModel) -> Double {
        (workout.exercises ?? []).flatMap { $0.sets ?? [] }
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    }

    private func sessionLine(exerciseID: UUID, in workout: WorkoutModel) -> String? {
        guard let match = matchingExercise(exerciseID: exerciseID, in: workout) else { return nil }
        let sets = (match.sets ?? [])
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .sorted { $0.order < $1.order }
        guard let first = sets.first else { return nil }
        let reps = sets.map { String($0.reps) }.joined(separator: ",")
        return "\(WorkoutSession.format(first.weightKg)) × \(reps)"
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

    /// Headline records only (e1RM) — the count the user sees; other kinds are cached silently.
    private func prCount(for workoutID: UUID) -> Int {
        let headline = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordModel> { $0.workoutID == workoutID && $0.kind == headline }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    // MARK: - Personal records (GymCore.PersonalRecords)

    /// Evaluates every `PRKind` per exercise and caches all of them (`PersonalRecordModel`), but
    /// the summary/banner still surfaces only the e1RM kind per exercise — matching the existing
    /// "one PR line per exercise" UI. The other kinds (maxWeight, volume, maxRepsAtWeight, …) are
    /// cached for `exerciseInfo(for:)`-style lookups and future screens without changing what the
    /// Finish summary shows.
    private func evaluatePRs(session: WorkoutSession, workout: WorkoutModel) -> [PersonalRecordInfo] {
        let latestDate = latestFinishedWorkoutDate(excluding: workout.id)
        return session.exercises.compactMap { entry -> PersonalRecordInfo? in
            let performed = performedSets(in: entry, date: workout.startedAt)
            guard !performed.isEmpty else { return nil }
            let records = PersonalRecords.evaluate(
                newSets: performed, existing: existingRecords(exerciseID: entry.exercise.id),
                workoutDate: workout.startedAt, isBackfilled: workout.isBackfilled,
                latestWorkoutDate: latestDate
            )
            for record in records {
                cacheRecord(record, exerciseID: entry.exercise.id, workoutID: workout.id)
            }
            guard let e1rm = records.first(where: { $0.kind == .e1rm }) else { return nil }
            return PersonalRecordInfo(
                exerciseName: entry.exercise.name, line: PersonalRecords.formatLine(e1rm)
            )
        }
    }

    /// The other finished workout's `startedAt` closest to now (excluding this one), used so a
    /// backfilled workout can't claim a PR against a session that happened later.
    private func latestFinishedWorkoutDate(excluding workoutID: UUID) -> Date? {
        finishedWorkoutsNewestFirst().first { $0.id != workoutID }?.startedAt
    }

    private func performedSets(in entry: WorkoutExerciseEntry, date: Date) -> [PerformedSet] {
        entry.sets.filter { $0.isDone && $0.kind.countsTowardStats }.map { setEntry in
            PerformedSet(
                kind: setEntry.kind, weightKg: setEntry.weightKg, reps: setEntry.reps,
                durationSeconds: setEntry.durationSeconds, date: date
            )
        }
    }

    /// Every cached record for this exercise, across all kinds — the `existing` bests that
    /// `PersonalRecords.evaluate` checks each new set against.
    private func existingRecords(exerciseID: UUID) -> [PersonalRecord] {
        let predicate = #Predicate<PersonalRecordModel> { $0.exerciseID == exerciseID }
        let models = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        return models.compactMap { model in
            guard let kind = PRKind(rawValue: model.kind) else { return nil }
            return PersonalRecord(
                kind: kind, value: model.value, weightKg: model.weightKg, reps: model.reps, date: model.date
            )
        }
    }

    /// Upserts one PR into the cache. `maxRepsAtWeight` keeps one row per weight (a lifter can
    /// hold separate rep records at 60 kg and 80 kg); every other kind keeps a single best row.
    private func cacheRecord(_ record: PersonalRecord, exerciseID: UUID, workoutID: UUID) {
        let kind = record.kind.rawValue
        let weight = record.weightKg
        let byWeightToo = record.kind == .maxRepsAtWeight
        let predicate = #Predicate<PersonalRecordModel> {
            $0.exerciseID == exerciseID && $0.kind == kind && (!byWeightToo || $0.weightKg == weight)
        }
        let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first
        let model = existing ?? PersonalRecordModel(exerciseID: exerciseID, kind: kind)
        if existing == nil { context.insert(model) }
        model.value = record.value
        model.weightKg = record.weightKg
        model.reps = record.reps
        model.date = record.date
        model.workoutID = workoutID
    }
}
