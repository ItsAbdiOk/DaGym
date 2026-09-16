import Foundation
import GymCore
import SwiftData

/// The live library read once into dictionaries, so resolving every exercise name in a
/// multi-thousand-row export is a hash lookup rather than a fetch per row (`exerciseID(seedID:)`
/// and `fetchExerciseModel(id:)` each used to hit SwiftData once per entry). Rows a run creates
/// are registered as it goes, so the second workout on a new name reuses the first's exercise.
///
/// Not `Sendable` on purpose: it holds `ExerciseModel`s, and lives entirely inside whichever
/// isolation built it — the main actor for `WorkoutImportService.apply`, `ImportActor` otherwise.
final class ImportExerciseLibrary {
    private var byID: [UUID: ExerciseModel] = [:]
    private var bySeedID: [String: ExerciseModel] = [:]
    /// The matcher's view of the same rows, built once alongside the dictionaries.
    let matchContext: ParseContext

    init(context: ModelContext) {
        let live = BackupService.liveExercises(context: context)
        for model in live {
            byID[model.id] = model
            if let seedID = model.seedID, bySeedID[seedID] == nil { bySeedID[seedID] = model }
        }
        let candidates = live.map {
            ParseContext.ExerciseCandidate(id: $0.id, name: $0.name, equipment: $0.equipment)
        }
        matchContext = ParseContext(unit: .kg, library: candidates)
    }

    func model(id: UUID) -> ExerciseModel? { byID[id] }

    func model(seedID: String) -> ExerciseModel? { bySeedID[seedID] }

    func register(_ model: ExerciseModel) {
        byID[model.id] = model
        if let seedID = model.seedID, bySeedID[seedID] == nil { bySeedID[seedID] = model }
    }
}

/// Writes parsed `ImportedWorkout`s into one `ModelContext`, one workout at a time, keeping the
/// per-run state (`report`, the name → exercise cache, the dedupe keys) between calls. The
/// main-actor `WorkoutImportService.apply` drives it in one go; `ImportActor` drives the same
/// writer in saved batches. Nothing here saves — the driver decides when.
final class WorkoutImportWriter {
    let context: ModelContext
    let library: ImportExerciseLibrary
    let source: ImportSource
    private(set) var report = WorkoutImportReport()
    private var exerciseCache: [String: UUID] = [:]
    private var seenKeys: Set<String>
    private var seenExternalIDs: Set<String> = []

    init(context: ModelContext, source: ImportSource, problems: [ImportProblem] = []) {
        self.context = context
        self.source = source
        library = ImportExerciseLibrary(context: context)
        seenKeys = WorkoutImportService.existingWorkoutKeys(context: context)
        report.problems = problems.map { "Line \($0.line): \($0.message)" }
    }

    /// Inserts `imported` unless a workout starting in the same minute (or carrying the same
    /// source id) is already in the store or earlier in this run. Returns how many `SetLogModel`
    /// rows it added — 0 for a skip — so a batching driver can count rows between saves.
    @discardableResult
    func insert(_ imported: ImportedWorkout) -> Int {
        let key = WorkoutImportService.workoutKey(imported)
        let isDuplicate = seenKeys.contains(key)
            || imported.externalID.map { seenExternalIDs.contains($0) } ?? false
        guard !isDuplicate else {
            report.workoutsSkipped += 1
            return 0
        }
        seenKeys.insert(key)
        if let externalID = imported.externalID { seenExternalIDs.insert(externalID) }
        let rows = insertWorkout(imported)
        report.workoutsImported += 1
        return rows
    }

    /// Inserts one imported workout as a finished, backfilled `WorkoutModel`, resolving each
    /// exercise name. Personal records are rebuilt once by the driver after every workout is in.
    private func insertWorkout(_ imported: ImportedWorkout) -> Int {
        let workout = Self.makeWorkoutModel(imported, source: source)
        context.insert(workout)
        var rows = 0
        for (order, exercise) in imported.exercises.enumerated() {
            let exerciseID = resolveExercise(exercise)
            guard let exerciseModel = library.model(id: exerciseID) else { continue }
            addExerciseEntry(exercise, order: order, model: exerciseModel, workout: workout)
            report.setsImported += exercise.sets.count
            rows += exercise.sets.count
        }
        // The rows are linked through `WorkoutExerciseModel.workout` alone. Assigning
        // `workout.exercises` as well makes SwiftData rebuild a relationship it is already
        // mid-way through updating, which traps — the trap `restoreWorkout` was rewritten to
        // avoid.
        return rows
    }

    /// Resolves an imported exercise to an id, creating a custom exercise the first time a run
    /// sees an unmatched name (subsequent rows with the same name reuse it). The new exercise's
    /// muscles come from the source's category or the name; its logging style from what the
    /// file's rows measured.
    func resolveExercise(_ exercise: ImportedExercise) -> UUID {
        let key = exercise.name.lowercased()
        if let cached = exerciseCache[key] { return cached }
        if let seeded = WorkoutImportService.seededExerciseID(for: exercise.name, library: library) {
            exerciseCache[key] = seeded
            return seeded
        }
        if let matched = WorkoutImportService.matchedExerciseID(
            exercise.name, context: library.matchContext
        ) {
            exerciseCache[key] = matched
            return matched
        }
        // `restSeconds: 0` means "use Settings → Default rest", as `createCustomExercise` writes.
        let model = ExerciseModel(
            name: exercise.name,
            primaryMuscles: ExerciseHints.primaryMuscles(name: exercise.name, category: exercise.category)
                .map(\.rawValue),
            equipment: "other", loggingStyle: Self.inventedStyle(for: exercise).rawKey, isCustom: true,
            restSeconds: 0
        )
        context.insert(model)
        library.register(model)
        exerciseCache[key] = model.id
        report.exercisesCreated += 1
        return model.id
    }

    private static func inventedStyle(for exercise: ImportedExercise) -> ExerciseInfo.LoggingStyle {
        let hint = ExerciseHints.loggingStyle(
            hasReps: exercise.sets.contains { $0.reps > 0 },
            hasTime: exercise.sets.contains { ($0.durationSeconds ?? 0) > 0 },
            hasDistance: exercise.sets.contains { ($0.distanceMeters ?? 0) > 0 }
        )
        switch hint {
        case .weightReps: return .weightReps
        case .bodyweightReps: return .bodyweightReps
        case .assisted: return .assisted
        case .weightedBodyweight: return .weightedBodyweight
        case .timedHold: return .timedHold
        case .cardio: return .cardio
        }
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

    private func addExerciseEntry(
        _ exercise: ImportedExercise, order: Int, model exerciseModel: ExerciseModel, workout: WorkoutModel
    ) {
        // `supersetGroup` carries the source's own grouping (Hevy's `superset_id`) through, so a
        // superset imports as a superset instead of two unrelated blocks.
        let entryModel = WorkoutExerciseModel(
            order: order, supersetGroup: exercise.supersetGroup, note: exercise.note,
            exercise: exerciseModel, workout: workout
        )
        context.insert(entryModel)
        // `workoutExercise:` is the whole link; `entryModel.sets` must not also be assigned.
        for set in Self.makeSetModels(exercise.sets, workoutExercise: entryModel, at: workout.startedAt) {
            context.insert(set)
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
