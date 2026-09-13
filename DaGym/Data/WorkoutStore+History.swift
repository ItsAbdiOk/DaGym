import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// Ends the session, computes PRs against the cache and returns a summary. Backfilled or
    /// otherwise earlier-dated workouts never claim a PR against a later-dated one.
    func finish(session: WorkoutSession) -> WorkoutSummary {
        sync(session: session)
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID) else {
            return WorkoutSummary(durationSeconds: 0, volumeKg: 0, setsDone: 0, prs: [], musclesHit: [:])
        }
        let endedAt = Date()
        workout.endedAt = endedAt
        let prs = evaluatePRs(session: session, workout: workout)
        save()
        return WorkoutSummary(
            durationSeconds: max(0, Int(endedAt.timeIntervalSince(workout.startedAt))),
            volumeKg: session.volumeKg, setsDone: session.setsDone, prs: prs, musclesHit: session.musclesHit
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

    // MARK: - Helpers

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

    private func prCount(for workoutID: UUID) -> Int {
        let predicate = #Predicate<PersonalRecordModel> { $0.workoutID == workoutID }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    // MARK: - Personal records (GymCore.PersonalRecords)

    /// One e1RM PR per exercise, evaluated with `GymCore.PersonalRecords.evaluate` against the
    /// cached best (`PersonalRecordModel`, kind "e1rm"). Only the e1RM kind is tracked in the
    /// cache today, even though `evaluate` can also surface maxWeight/volume/etc — see the
    /// wiring report for the follow-up to cache those too.
    private func evaluatePRs(session: WorkoutSession, workout: WorkoutModel) -> [PersonalRecordInfo] {
        let latestDate = latestFinishedWorkoutDate(excluding: workout.id)
        return session.exercises.compactMap { entry -> PersonalRecordInfo? in
            let performed = performedSets(in: entry, date: workout.startedAt)
            guard !performed.isEmpty else { return nil }
            let records = PersonalRecords.evaluate(
                newSets: performed, existing: existingE1RMRecords(exerciseID: entry.exercise.id),
                workoutDate: workout.startedAt, isBackfilled: workout.isBackfilled,
                latestWorkoutDate: latestDate
            )
            guard let record = records.first(where: { $0.kind == .e1rm }) else { return nil }
            return cacheE1RM(
                record, exerciseID: entry.exercise.id, exerciseName: entry.exercise.name,
                workoutID: workout.id
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

    private func existingE1RMRecords(exerciseID: UUID) -> [PersonalRecord] {
        let predicate = #Predicate<PersonalRecordModel> { $0.exerciseID == exerciseID && $0.kind == "e1rm" }
        let fetched = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first
        guard let model = fetched else { return [] }
        return [
            PersonalRecord(
                kind: .e1rm, value: model.value, weightKg: model.weightKg, reps: model.reps, date: model.date
            )
        ]
    }

    private func cacheE1RM(
        _ record: PersonalRecord, exerciseID: UUID, exerciseName: String, workoutID: UUID
    ) -> PersonalRecordInfo {
        let predicate = #Predicate<PersonalRecordModel> { $0.exerciseID == exerciseID && $0.kind == "e1rm" }
        let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first
        let model = existing ?? PersonalRecordModel(exerciseID: exerciseID, kind: "e1rm")
        if existing == nil { context.insert(model) }
        model.value = record.value
        model.weightKg = record.weightKg
        model.reps = record.reps
        model.date = record.date
        model.workoutID = workoutID
        return PersonalRecordInfo(exerciseName: exerciseName, line: PersonalRecords.formatLine(record))
    }
}
