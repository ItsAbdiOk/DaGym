import Foundation
import GymCore
import SwiftData

/// One earned record, formatted for display — see `GymCore.PersonalRecords.formatLine`.
struct PersonalRecordLine: Identifiable, Hashable {
    var id = UUID()
    var kindLabel: String
    var line: String
    var date: Date
}

/// Every cached record for one exercise, for `PersonalRecordsView`.
struct ExerciseRecords: Identifiable {
    var id: UUID
    var exerciseName: String
    var records: [PersonalRecordLine]
}

extension WorkoutStore {
    /// All cached `PersonalRecordModel`s, grouped by exercise and sorted alphabetically.
    /// Records within an exercise are ordered by kind, then newest first. `unit` controls how
    /// each line is formatted; defaults to kg for callers that haven't gone unit-aware yet.
    func personalRecords(unit: WeightUnit = .kg) -> [ExerciseRecords] {
        let models = fetch(FetchDescriptor<PersonalRecordModel>())
        let grouped = Dictionary(grouping: models) { $0.exerciseID }
        return grouped
            .compactMap { exerciseID, models -> ExerciseRecords? in
                guard let exerciseID, let exerciseModel = fetchExerciseModel(id: exerciseID) else {
                    return nil
                }
                let order = PRKind.allCases
                let lines = models
                    .sorted { lhs, rhs in
                        let li = order.firstIndex(of: PRKind(rawValue: lhs.kind) ?? .e1rm) ?? 0
                        let ri = order.firstIndex(of: PRKind(rawValue: rhs.kind) ?? .e1rm) ?? 0
                        return li != ri ? li < ri : lhs.date > rhs.date
                    }
                    .map { self.personalRecordLine($0, unit: unit) }
                return ExerciseRecords(id: exerciseID, exerciseName: exerciseModel.name, records: lines)
            }
            .sorted { $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending }
    }

    private func personalRecordLine(_ model: PersonalRecordModel, unit: WeightUnit) -> PersonalRecordLine {
        let kind = PRKind(rawValue: model.kind) ?? .e1rm
        let record = PersonalRecord(
            kind: kind, value: model.value, weightKg: model.weightKg, reps: model.reps, date: model.date
        )
        return PersonalRecordLine(
            kindLabel: Self.kindLabel(kind), line: PersonalRecords.formatLine(record, unit: unit),
            date: model.date
        )
    }

    private static func kindLabel(_ kind: PRKind) -> String {
        switch kind {
        case .e1rm: "Estimated 1RM"
        case .maxWeight: "Heaviest weight"
        case .maxRepsAtWeight: "Most reps"
        case .volume: "Volume"
        case .longestHold: "Longest hold"
        case .leastAssistance: "Least assistance"
        }
    }
}

// MARK: - Evaluation, event log and rebuild (GymCore.PersonalRecords)

extension WorkoutStore {
    /// Headline records only (e1RM) — the count the user sees; other kinds are logged silently.
    /// Counts `PersonalRecordEventModel` rows, which are append-only, so a workout's PR count
    /// doesn't decay when a later session beats it.
    func prCount(for workoutID: UUID) -> Int {
        let headline = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordEventModel> {
            $0.workoutID == workoutID && $0.kind == headline
        }
        return fetchCount(FetchDescriptor(predicate: predicate))
    }

    /// Headline (e1RM) records set by workouts started in `[from, to)`, from the event log.
    func prCount(from: Date, to: Date) -> Int {
        let headline = PRKind.e1rm.rawValue
        let predicate = #Predicate<PersonalRecordEventModel> {
            $0.kind == headline && $0.date >= from && $0.date < to
        }
        return fetchCount(FetchDescriptor(predicate: predicate))
    }

    // MARK: - Personal records (GymCore.PersonalRecords)

    /// Evaluates every `PRKind` per exercise and caches all of them (`PersonalRecordModel`), but
    /// the summary/banner still surfaces only the e1RM kind per exercise — matching the existing
    /// "one PR line per exercise" UI. The other kinds (maxWeight, volume, maxRepsAtWeight, …) are
    /// cached for `exerciseInfo(for:)`-style lookups and future screens without changing what the
    /// Finish summary shows.
    func evaluatePRs(
        session: WorkoutSession, workout: WorkoutModel, unit: WeightUnit = .kg
    ) -> [PersonalRecordInfo] {
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
                logRecordEvent(record, exerciseID: entry.exercise.id, workoutID: workout.id)
            }
            guard let e1rm = records.first(where: { $0.kind == .e1rm }) else { return nil }
            return PersonalRecordInfo(
                exerciseName: entry.exercise.name, line: PersonalRecords.formatLine(e1rm, unit: unit)
            )
        }
    }

    /// Throws away the PR cache and event log and replays every finished workout, oldest first,
    /// so both reflect exactly the sets that still exist. Used after deleting a workout and after
    /// a backup import; cheap enough for a settings "recompute" too.
    func rebuildPersonalRecords() {
        deleteAll(PersonalRecordModel.self)
        deleteAll(PersonalRecordEventModel.self)
        let workouts = finishedWorkoutModelsNewestFirst().reversed()
        for workout in workouts {
            replayRecords(in: workout)
        }
        save()
    }

    private func replayRecords(in workout: WorkoutModel) {
        for exerciseModel in (workout.exercises ?? []).sorted(by: { $0.order < $1.order }) {
            guard let exercise = exerciseModel.exercise else { continue }
            let entry = WorkoutExerciseEntry(model: exerciseModel, exercise: ExerciseInfo(model: exercise))
            let performed = performedSets(in: entry, date: workout.startedAt)
            guard !performed.isEmpty else { continue }
            // Replayed in date order, so every earlier workout is already in the cache and no
            // later one is: a backfill can never claim a record against a session after it.
            let records = PersonalRecords.evaluate(
                newSets: performed, existing: existingRecords(exerciseID: exercise.id),
                workoutDate: workout.startedAt, isBackfilled: false, latestWorkoutDate: nil
            )
            for record in records {
                cacheRecord(record, exerciseID: exercise.id, workoutID: workout.id)
                logRecordEvent(record, exerciseID: exercise.id, workoutID: workout.id)
            }
        }
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) {
        let models = fetch(FetchDescriptor<Model>())
        models.forEach(context.delete)
    }

    private func logRecordEvent(_ record: PersonalRecord, exerciseID: UUID, workoutID: UUID) {
        context.insert(
            PersonalRecordEventModel(
                exerciseID: exerciseID, workoutID: workoutID, kind: record.kind.rawValue,
                value: record.value, weightKg: record.weightKg, reps: record.reps, date: record.date
            )
        )
    }

    /// The other finished workout's `startedAt` closest to now (excluding this one), used so a
    /// backfilled workout can't claim a PR against a session that happened later.
    private func latestFinishedWorkoutDate(excluding workoutID: UUID) -> Date? {
        finishedWorkoutModelsNewestFirst().first { $0.id != workoutID }?.startedAt
    }

    private func performedSets(in entry: WorkoutExerciseEntry, date: Date) -> [PerformedSet] {
        let isBodyweightStyle = entry.exercise.loggingStyle == .bodyweightReps
            || entry.exercise.loggingStyle == .assisted || entry.exercise.loggingStyle == .weightedBodyweight
        let bodyweightKg = isBodyweightStyle ? latestBodyMeasurement(asOf: date)?.bodyweightKg : nil
        return entry.sets.filter { $0.isDone && $0.kind.countsTowardStats }.map { setEntry in
            PerformedSet(
                kind: setEntry.kind, weightKg: setEntry.weightKg, reps: setEntry.reps,
                durationSeconds: setEntry.durationSeconds, assistanceKg: setEntry.assistanceKg,
                bodyweightKg: bodyweightKg, date: date
            )
        }
    }

    /// Every cached record for this exercise, across all kinds — the `existing` bests that
    /// `PersonalRecords.evaluate` checks each new set against.
    private func existingRecords(exerciseID: UUID) -> [PersonalRecord] {
        let predicate = #Predicate<PersonalRecordModel> { $0.exerciseID == exerciseID }
        let models = fetch(FetchDescriptor(predicate: predicate))
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
        let existing = fetchFirst(FetchDescriptor(predicate: predicate))
        let model = existing ?? PersonalRecordModel(exerciseID: exerciseID, kind: kind)
        if existing == nil { context.insert(model) }
        model.value = record.value
        model.weightKg = record.weightKg
        model.reps = record.reps
        model.date = record.date
        model.workoutID = workoutID
    }
}
