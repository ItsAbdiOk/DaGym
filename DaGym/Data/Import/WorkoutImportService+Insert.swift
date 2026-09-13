import Foundation
import GymCore
import SwiftData

/// Groups the fixed-for-one-`apply()`-call context (store, matcher context, source tag) so the
/// per-workout insert functions don't thread three separate parameters each.
struct ImportEnvironment {
    var store: WorkoutStore
    var context: ParseContext
    var source: ImportSource
}

/// The per-workout insert path for `WorkoutImportService.apply`, split out to keep the main file
/// focused on preview/dedupe/matching.
extension WorkoutImportService {
    /// Inserts one imported workout as a finished, backfilled `WorkoutModel`, resolving each
    /// exercise name and caching any new personal records. Returns the exercise ids touched, for
    /// the caller's bookkeeping (none of today's screens need it, but it keeps the return value
    /// honest about what changed).
    static func insertWorkout(
        _ imported: ImportedWorkout, environment: ImportEnvironment, exerciseCache: inout [String: UUID],
        latestDateSoFar: Date?, report: inout WorkoutImportReport
    ) -> [UUID] {
        let workout = makeWorkoutModel(imported, source: environment.source)
        environment.store.context.insert(workout)

        var touchedExerciseIDs: [UUID] = []
        var exerciseModels: [WorkoutExerciseModel] = []
        for (order, exercise) in imported.exercises.enumerated() {
            let exerciseID = resolveExercise(
                exercise.name, store: environment.store, context: environment.context,
                exerciseCache: &exerciseCache, report: &report
            )
            guard let exerciseModel = environment.store.fetchExerciseModel(id: exerciseID) else { continue }
            let entryModel = addExerciseEntry(
                exercise, order: order, model: exerciseModel, workout: workout, store: environment.store
            )
            report.setsImported += exercise.sets.count
            touchedExerciseIDs.append(exerciseID)
            exerciseModels.append(entryModel)
        }
        workout.exercises = exerciseModels

        for (exerciseID, exerciseModel) in zip(touchedExerciseIDs, exerciseModels) {
            cachePersonalRecords(
                exerciseID: exerciseID, exerciseModel: exerciseModel, workout: workout,
                store: environment.store, latestDateSoFar: latestDateSoFar
            )
        }
        return touchedExerciseIDs
    }

    /// `WorkoutModel.endedAt == nil` means "still in progress" everywhere else in the app
    /// (history, PR evaluation, lifetime stats), so a source with no end time (FitNotes) gets a
    /// default one-hour duration rather than silently vanishing from those queries.
    private static func makeWorkoutModel(_ imported: ImportedWorkout, source: ImportSource) -> WorkoutModel {
        let endedAt = imported.endedAt ?? imported.startedAt.addingTimeInterval(3600)
        return WorkoutModel(
            title: imported.title, startedAt: imported.startedAt, endedAt: endedAt,
            notes: imported.notes, isBackfilled: true, sourceDevice: source.sourceDeviceTag
        )
    }

    private static func addExerciseEntry(
        _ exercise: ImportedExercise, order: Int, model exerciseModel: ExerciseModel,
        workout: WorkoutModel, store: WorkoutStore
    ) -> WorkoutExerciseModel {
        let entryModel = WorkoutExerciseModel(
            order: order, note: exercise.note, exercise: exerciseModel, workout: workout
        )
        store.context.insert(entryModel)
        let sets = makeSetModels(exercise.sets, workoutExercise: entryModel, at: workout.startedAt)
        entryModel.sets = sets
        for set in sets { store.context.insert(set) }
        return entryModel
    }

    private static func makeSetModels(
        _ sets: [ImportedSet], workoutExercise: WorkoutExerciseModel, at date: Date
    ) -> [SetLogModel] {
        sets.enumerated().map { order, set in
            SetLogModel(
                order: order, kind: set.kind.rawValue, weightKg: set.weightKg, reps: set.reps,
                durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters, rpe: set.rpe,
                isCompleted: true, completedAt: date, workoutExercise: workoutExercise
            )
        }
    }

    // MARK: - Personal records

    private static func cachePersonalRecords(
        exerciseID: UUID, exerciseModel: WorkoutExerciseModel, workout: WorkoutModel, store: WorkoutStore,
        latestDateSoFar: Date?
    ) {
        let performed = (exerciseModel.sets ?? [])
            .filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .map {
                PerformedSet(
                    kind: $0.setKind, weightKg: $0.weightKg, reps: $0.reps,
                    durationSeconds: $0.durationSeconds, date: workout.startedAt
                )
            }
        guard !performed.isEmpty else { return }
        let records = PersonalRecords.evaluate(
            newSets: performed, existing: existingRecords(exerciseID: exerciseID, store: store),
            workoutDate: workout.startedAt, isBackfilled: true, latestWorkoutDate: latestDateSoFar
        )
        for record in records {
            upsertRecord(record, exerciseID: exerciseID, workoutID: workout.id, store: store)
        }
    }

    private static func existingRecords(exerciseID: UUID, store: WorkoutStore) -> [PersonalRecord] {
        let predicate = #Predicate<PersonalRecordModel> { $0.exerciseID == exerciseID }
        let models = (try? store.context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        return models.compactMap { model in
            guard let kind = PRKind(rawValue: model.kind) else { return nil }
            return PersonalRecord(
                kind: kind, value: model.value, weightKg: model.weightKg, reps: model.reps, date: model.date
            )
        }
    }

    /// Mirrors `WorkoutStore.cacheRecord`: one row per exercise/kind, except `maxRepsAtWeight`
    /// which keeps one row per weight.
    private static func upsertRecord(
        _ record: PersonalRecord, exerciseID: UUID, workoutID: UUID, store: WorkoutStore
    ) {
        let kind = record.kind.rawValue
        let weight = record.weightKg
        let byWeightToo = record.kind == .maxRepsAtWeight
        let predicate = #Predicate<PersonalRecordModel> {
            $0.exerciseID == exerciseID && $0.kind == kind && (!byWeightToo || $0.weightKg == weight)
        }
        let existing = (try? store.context.fetch(FetchDescriptor(predicate: predicate)))?.first
        let model = existing ?? PersonalRecordModel(exerciseID: exerciseID, kind: kind)
        if existing == nil { store.context.insert(model) }
        model.value = record.value
        model.weightKg = record.weightKg
        model.reps = record.reps
        model.date = record.date
        model.workoutID = workoutID
    }
}
