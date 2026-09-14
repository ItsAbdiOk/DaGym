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
    /// exercise name. Personal records are rebuilt once by `apply` after every workout is in.
    /// Returns the exercise ids touched, for the caller's bookkeeping (none of today's screens
    /// need it, but it keeps the return value honest about what changed).
    static func insertWorkout(
        _ imported: ImportedWorkout, environment: ImportEnvironment, exerciseCache: inout [String: UUID],
        report: inout WorkoutImportReport
    ) -> [UUID] {
        let workout = makeWorkoutModel(imported, source: environment.source)
        environment.store.context.insert(workout)

        var touchedExerciseIDs: [UUID] = []
        for (order, exercise) in imported.exercises.enumerated() {
            let exerciseID = resolveExercise(
                exercise, store: environment.store, context: environment.context,
                exerciseCache: &exerciseCache, report: &report
            )
            guard let exerciseModel = environment.store.fetchExerciseModel(id: exerciseID) else { continue }
            addExerciseEntry(
                exercise, order: order, model: exerciseModel, workout: workout, store: environment.store
            )
            report.setsImported += exercise.sets.count
            touchedExerciseIDs.append(exerciseID)
        }
        // The rows are linked through `WorkoutExerciseModel.workout` alone. Assigning
        // `workout.exercises` as well makes SwiftData rebuild a relationship it is already
        // mid-way through updating, which traps — the trap `restoreWorkout` was rewritten to
        // avoid.
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
    ) {
        // `supersetGroup` carries the source's own grouping (Hevy's `superset_id`) through, so a
        // superset imports as a superset instead of two unrelated blocks.
        let entryModel = WorkoutExerciseModel(
            order: order, supersetGroup: exercise.supersetGroup, note: exercise.note,
            exercise: exerciseModel, workout: workout
        )
        store.context.insert(entryModel)
        // `workoutExercise:` is the whole link; `entryModel.sets` must not also be assigned.
        for set in makeSetModels(exercise.sets, workoutExercise: entryModel, at: workout.startedAt) {
            store.context.insert(set)
        }
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
}
