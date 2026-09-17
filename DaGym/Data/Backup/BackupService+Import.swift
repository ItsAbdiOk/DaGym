import Foundation
import GymCore
import SwiftData
import os

private let backupSignposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")

extension BackupService {
    // MARK: - Import

    /// Merges a decoded document into `context`. Never overwrites: matched
    /// by id, then (for exercises/routines) by name. Existing workouts with
    /// the same id are always skipped, so re-importing the same file twice
    /// never duplicates anything. The PR cache is rebuilt from history at the
    /// end, so Records and Milestones reflect the imported workouts.
    ///
    /// `store` is the live `WorkoutStore` over `context` when the app is the caller: the PR
    /// rebuild then runs on it and every save goes through it, so `changeToken` bumps and the
    /// History/Home screens keyed on it redraw. A throwaway store used to do the rebuild, and
    /// nothing keyed on the token noticed the import until some unrelated save.
    /// `thumbnails` are progress-photo thumbnails already generated off the main actor
    /// (`thumbnails(for:)`); nil means "generate inline", which tests and the reset path use.
    @discardableResult
    static func `import`(
        document: BackupDocument, context: ModelContext, mode: ImportMode = .merge,
        baseline: SeedBaseline = SeedBaseline(), photoContext: ModelContext? = nil,
        healthContext: ModelContext? = nil, preferences: Preferences? = nil,
        store: WorkoutStore? = nil, thumbnails: [UUID: Data]? = nil
    ) -> ImportReport {
        let interval = backupSignposter.beginInterval("backupImport")
        defer { backupSignposter.endInterval("backupImport", interval) }
        var report = ImportReport()
        // "Reset everything" deletes every `ExerciseModel`, and re-seeding otherwise only happens
        // at launch. Without this, a restore in the same session resolves every seeded exercise
        // against an empty library: each workout imports with its sets dropped and a "not found"
        // problem for every row. Seed first, then resolve.
        seedLibraryIfTheFileNeedsIt(document, context: context)
        let exerciseIndex = ExerciseIndex(context: context)
        importExercises(
            document.exercises, index: exerciseIndex, baseline: baseline, context: context, report: &report
        )
        importRoutines(document.routines, index: exerciseIndex, context: context, report: &report)
        let importedWorkouts = importWorkouts(
            document.workouts, index: exerciseIndex, context: context, report: &report
        )
        importBodyMeasurements(document.bodyMeasurements, context: context, report: &report)
        importEquipmentProfiles(document.equipmentProfiles, context: context, report: &report)
        importPrograms(document.programs ?? [], context: context)
        importAchievements(document.achievements ?? [], context: context)
        importSchedule(document.schedule, context: context)
        importExtras(
            document, index: exerciseIndex, context: context, photoContext: photoContext,
            healthContext: healthContext, thumbnails: thumbnails, report: &report
        )
        do {
            try context.save()
        } catch {
            report.problems.append("Saving the import failed: \(error.localizedDescription)")
            return report
        }
        applyPreferences(document.preferences, to: preferences ?? Preferences())
        report.preferencesRestored = true
        if importedWorkouts > 0 {
            let live = store ?? WorkoutStore(context: context, photoContext: nil)
            // Stamped after the save: the imported rows are linked through their inverses only,
            // which SwiftData populates on save — stamping earlier reads them as empty.
            live.restampWorkoutTotalsAfterRemoteChange()
            live.rebuildPersonalRecords()
        }
        store?.noteExternalSave()
        return report
    }

    /// The Settings entry point: progress-photo decode/resize off the main actor first, then the
    /// main store's rows through `ImportActor` on its own context (batched saves, `progress`
    /// called as each batch lands, cancellable between batches), and finally the two local-only
    /// stores and the preferences here on the main actor. Ends by telling `store` about the
    /// external writes the way a CloudKit merge would (`absorbExternalImport`), so totals, PRs and
    /// the cached catalogue are right — on a cancel too, for whatever batches had landed.
    ///
    /// Throws `CancellationError` when the calling task is cancelled mid-restore; saved batches
    /// stay and re-running the same file skips them by id.
    static func `import`(
        document: BackupDocument, store: WorkoutStore, preferences: Preferences,
        progress: @escaping ImportActor.ProgressHandler = { _ in }, history: ImportHistoryLog = .shared
    ) async throws -> ImportReport {
        let photos = document.progressPhotos ?? []
        let thumbnails = await Task.detached(priority: .userInitiated) { thumbnails(for: photos) }.value
        // Seeding needs the main actor; saved before the actor's context reads the library.
        seedLibraryIfTheFileNeedsIt(document, context: store.context)
        store.save()
        let baseline = SeedBaseline()
        let actor = ImportActor(modelContainer: store.context.container)
        var report: ImportReport
        do {
            report = try await actor.restore(document, baseline: baseline, progress: progress)
        } catch {
            store.absorbExternalImport(rebuildRecords: true)
            throw error
        }
        importPhotos(photos, context: store.photoContext, thumbnails: thumbnails, report: &report)
        importHealth(document.healthImports, context: store.healthContext, report: &report)
        applyPreferences(document.preferences, to: preferences)
        report.preferencesRestored = true
        store.absorbExternalImport(rebuildRecords: report.workoutsImported > 0)
        history.record(.backup(report))
        return report
    }

    /// Seeds the bundled exercise library when the store has none.
    ///
    /// Called by `DataSettingsSection.performReset`, the only place `WorkoutStore.wipeAllData` is
    /// invoked from: the wipe deletes every `ExerciseModel` and seeding otherwise only happens at
    /// launch, so without this the app runs on an empty library until the next cold start. A
    /// single count query, and a no-op in every normal case.
    static func ensureExerciseLibrary(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<ExerciseModel>())) ?? 0
        guard count == 0 else { return }
        ExerciseSeeder.seedIfNeeded(context: context)
    }

    /// The same guard, but only when the file actually references built-in exercises — a backup of
    /// nothing but custom exercises has no use for 1,466 seeded rows, and pulling them in would
    /// change what a merge means for every other caller.
    private static func seedLibraryIfTheFileNeedsIt(
        _ document: BackupDocument, context: ModelContext
    ) {
        let needsSeeds = document.exercises.contains { $0.seedID != nil }
            || document.routines.contains { $0.exercises.contains { $0.exerciseSeedID != nil } }
            || document.workouts.contains { $0.exercises.contains { $0.exerciseSeedID != nil } }
        guard needsSeeds else { return }
        ensureExerciseLibrary(context: context)
    }

    /// Looks up `ExerciseModel`s by seedID/id/name, kept in memory for the
    /// duration of one import so routines and workouts can resolve exercises
    /// (including ones this same import just inserted).
    final class ExerciseIndex {
        private var bySeedID: [String: ExerciseModel] = [:]
        private var byID: [UUID: ExerciseModel] = [:]
        private var byName: [String: ExerciseModel] = [:]

        /// Built from **live** rows only. A seed tombstone shares its survivor's `seedID`, so
        /// indexing one could shadow the survivor and re-point every imported routine slot and
        /// logged set at a row the whole app hides — the import would "succeed" and the
        /// exercise would simply not be there.
        init(context: ModelContext) {
            for model in BackupService.liveExercises(context: context) { register(model) }
        }

        func register(_ model: ExerciseModel) {
            byID[model.id] = model
            byName[model.name.lowercased()] = model
            if let seedID = model.seedID { bySeedID[seedID] = model }
        }

        func find(seedID: String?, id: UUID?, name: String) -> ExerciseModel? {
            if let seedID, let model = bySeedID[seedID] { return model }
            if let id, let model = byID[id] { return model }
            return byName[name.lowercased()]
        }
    }

    nonisolated static func importExercises(
        _ items: [BackupExercise], index: ExerciseIndex, baseline: SeedBaseline, context: ModelContext,
        report: inout ImportReport
    ) {
        for item in items {
            if let existing = index.find(seedID: item.seedID, id: item.id, name: item.name) {
                applyOverride(item, to: existing, baseline: baseline)
                continue
            }
            guard item.seedID == nil else {
                report.problems.append("Skipped \"\(item.name)\": no matching built-in exercise.")
                continue
            }
            let model = ExerciseModel(
                id: item.id, name: item.name, primaryMuscles: item.primaryMuscles,
                secondaryMuscles: item.secondaryMuscles, equipment: item.equipment,
                mechanic: item.mechanic, loggingStyle: item.loggingStyle, isPerSide: item.isPerSide,
                isCustom: true, isFavorite: item.isFavorite, barType: item.barType,
                incrementKg: item.incrementKg, restSeconds: item.restSeconds,
                instructions: item.instructions, notes: item.notes, createdAt: item.createdAt,
                machine: item.machine
            )
            context.insert(model)
            index.register(model)
            report.exercisesImported += 1
        }
    }

    /// Applies favourite/rest/increment/bar/notes overrides onto an already-known exercise
    /// (seeded or custom) — only where the backup differs from the seeded value, so a row the
    /// user never touched on the exporting device can't undo an edit made on this one.
    nonisolated static func applyOverride(
        _ item: BackupExercise, to model: ExerciseModel, baseline: SeedBaseline
    ) {
        let seeded = baseline.values(for: item.seedID)
        if item.isFavorite { model.isFavorite = true }
        if baseline.isRestOverride(item.restSeconds, seedID: item.seedID) {
            model.restSeconds = item.restSeconds
        }
        if item.incrementKg != seeded.incrementKg { model.incrementKg = item.incrementKg }
        if item.barType != seeded.barType { model.barType = item.barType }
        if item.machine != seeded.machine { model.machine = item.machine }
        if model.notes.isEmpty { model.notes = item.notes }
    }

    nonisolated static func importRoutines(
        _ items: [BackupRoutine], index: ExerciseIndex, context: ModelContext, report: inout ImportReport
    ) {
        // Tombstones included on purpose: an older file can carry both halves of a fold, and a
        // routine whose local row is a tombstone is already represented by its survivor. Matching
        // it keeps the id unique and lets `dedupeRoutines()` converge the rest.
        // A `Set`, not `Dictionary(uniqueKeysWithValues:)`, which traps on a repeated key: a store
        // can hold two routines with one id (an earlier file that carried the same routine twice,
        // or an unmerged sync ghost), and a restore is the wrong moment to crash over it.
        var existingIDs = Set(((try? context.fetch(FetchDescriptor<RoutineModel>())) ?? []).map(\.id))
        // Tracked as the loop goes so a file that carries the same routine twice inserts it once.
        for item in items where !existingIDs.contains(item.id) {
            existingIDs.insert(item.id)
            let routine = RoutineModel(
                id: item.id, name: item.name, notes: item.notes, progressionRule: item.progressionRule,
                repRangeLow: item.repRangeLow, repRangeHigh: item.repRangeHigh,
                progressionRuleJSON: item.resolvedRule.map(ProgressionRuleCoding.encode) ?? "",
                createdAt: item.createdAt ?? Date(),
                updatedAt: item.updatedAt ?? Date(), sortOrder: item.sortOrder,
                isArchived: item.isArchived ?? false,
                importedFromID: item.importedFromID,
                symbolName: item.symbolName ?? "dumbbell", tint: item.tint ?? "coral"
            )
            context.insert(routine)
            // Linked through `RoutineExerciseModel.routine` only — assigning `routine.exercises`
            // as well makes SwiftData rebuild a relationship it is already mid-way through
            // updating, the trap `restoreWorkout` was rewritten to avoid.
            for draft in item.exercises {
                _ = makeRoutineExercise(
                    draft, index: index, routine: routine, context: context, report: &report
                )
            }
            report.routinesImported += 1
        }
    }

    nonisolated static func makeRoutineExercise(
        _ draft: BackupRoutineExercise, index: ExerciseIndex, routine: RoutineModel,
        context: ModelContext, report: inout ImportReport
    ) -> RoutineExerciseModel? {
        let match = index.find(seedID: draft.exerciseSeedID, id: nil, name: draft.exerciseName)
        guard let exercise = match else {
            report.problems.append(
                "Skipped \"\(draft.exerciseName)\" in routine \"\(routine.name)\": exercise not found."
            )
            return nil
        }
        let model = RoutineExerciseModel(
            order: draft.order, supersetGroup: draft.supersetGroup,
            restOverrideSeconds: draft.restOverrideSeconds, note: draft.note,
            progressionRuleJSON: draft.resolvedRule.map(ProgressionRuleCoding.encode),
            stallJSON: Self.stallJSON(draft.resolvedStall),
            trainingMaxKg: draft.trainingMaxKg, excludeFromProgression: draft.excludeFromProgression ?? false,
            exercise: exercise, routine: routine
        )
        context.insert(model)
        // `routineExercise:` is the whole link; `model.plannedSets` must not also be assigned.
        for set in draft.plannedSets {
            context.insert(PlannedSetModel(
                order: set.order, kind: set.kind, targetReps: set.targetReps,
                targetRepsHigh: set.targetRepsHigh, targetWeightKg: finite(set.targetWeightKg),
                targetRPE: finite(set.targetRPE), targetSeconds: set.targetSeconds,
                targetDistanceMeters: finite(set.targetDistanceMeters), routineExercise: model
            ))
        }
        return model
    }

    /// Returns how many workouts were inserted, so the caller knows whether a PR rebuild is due.
    nonisolated static func importWorkouts(
        _ items: [BackupWorkout], index: ExerciseIndex, context: ModelContext, report: inout ImportReport
    ) -> Int {
        var existingIDs = existingWorkoutIDs(context: context)
        var inserted = 0
        for item in items where insertWorkout(
            item, existingIDs: &existingIDs, index: index, context: context, report: &report
        ) != nil {
            inserted += 1
        }
        return inserted
    }

    nonisolated static func existingWorkoutIDs(context: ModelContext) -> Set<UUID> {
        Set(((try? context.fetch(FetchDescriptor<WorkoutModel>())) ?? []).map(\.id))
    }

    /// One workout of `importWorkouts`, shared with `ImportActor`'s batched restore. `existingIDs`
    /// grows as the loop goes — `insert` rather than a one-off check — so the same workout twice
    /// in one file imports once. Returns the inserted model, or nil for a skip.
    @discardableResult
    nonisolated static func insertWorkout(
        _ item: BackupWorkout, existingIDs: inout Set<UUID>, index: ExerciseIndex, context: ModelContext,
        report: inout ImportReport
    ) -> WorkoutModel? {
        guard existingIDs.insert(item.id).inserted else {
            report.workoutsSkipped += 1
            return nil
        }
        let workout = WorkoutModel(
            id: item.id, title: item.title, startedAt: item.startedAt, endedAt: item.endedAt,
            notes: item.notes, isBackfilled: item.isBackfilled, routineID: item.routineID,
            routineName: item.routineName, bodyweightKg: item.bodyweightKg,
            sourceDevice: item.sourceDevice, healthKitID: item.healthKitID
        )
        context.insert(workout)
        // Linked through `WorkoutExerciseModel.workout` only — see `importRoutines`. Entry ids
        // are re-keyed when a file repeats one: `WorkoutStore.sync(session:)` indexes a
        // workout's entries (and each entry's sets) by id with `uniqueKeysWithValues`, so a
        // duplicate imported verbatim trapped the first time the workout was resumed or edited.
        var entryIDs = Set<UUID>()
        for var draft in item.exercises {
            if !entryIDs.insert(draft.id).inserted { draft.id = UUID() }
            _ = makeWorkoutExercise(
                draft, index: index, workout: workout, context: context, report: &report
            )
        }
        report.workoutsImported += 1
        return workout
    }

    /// Logged history is irreplaceable, so an unresolvable exercise is *recreated* as a custom
    /// one rather than taking the sets down with it — including the placeholder rows an export
    /// writes for history whose custom exercise had already been deleted. Dropping the row (what
    /// this used to do) silently deleted real training data during a restore.
    nonisolated static func makeWorkoutExercise(
        _ draft: BackupWorkoutExercise, index: ExerciseIndex, workout: WorkoutModel,
        context: ModelContext, report: inout ImportReport
    ) -> WorkoutExerciseModel? {
        let match = index.find(seedID: draft.exerciseSeedID, id: nil, name: draft.exerciseName)
            ?? recreate(draft, workout: workout, index: index, context: context, report: &report)
        guard let exercise = match else { return nil }
        let model = WorkoutExerciseModel(
            id: draft.id, order: draft.order, supersetGroup: draft.supersetGroup, note: draft.note,
            wasSubstitution: draft.wasSubstitution, wasPlannedDeload: draft.wasPlannedDeload ?? false,
            excludedFromProgression: draft.excludedFromProgression ?? false,
            routineID: draft.routineID, exercise: exercise, workout: workout
        )
        context.insert(model)
        // `workoutExercise:` is the whole link; `model.sets` must not also be assigned. A repeated
        // set id gets a fresh one, for the reason given in `importWorkouts`.
        var setIDs = Set<UUID>()
        for set in draft.sets {
            let id = setIDs.insert(set.id).inserted ? set.id : UUID()
            // Non-finite numbers can't come from a `.json` file (the decoder rejects them) but can
            // from any other producer of a `BackupDocument`; stored, they make every later export
            // throw, so they're dropped here rather than trusted.
            context.insert(SetLogModel(
                id: id, order: set.order, kind: set.kind, weightKg: finite(set.weightKg) ?? 0,
                reps: set.reps, durationSeconds: set.durationSeconds,
                distanceMeters: finite(set.distanceMeters), inclinePercent: finite(set.inclinePercent),
                assistanceKg: finite(set.assistanceKg), rpe: finite(set.rpe),
                isCompleted: set.isCompleted, completedAt: set.completedAt,
                prescriptionReason: set.prescriptionReason, workoutExercise: model
            ))
        }
        return model
    }

    /// `value` when it is a real number, `nil` for NaN or an infinity (see `makeWorkoutExercise`).
    nonisolated static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Recreates a missing exercise as a custom one so its sets survive. `nil` only for a draft
    /// with no usable name at all, which has nothing to recreate from.
    nonisolated static func recreate(
        _ draft: BackupWorkoutExercise, workout: WorkoutModel, index: ExerciseIndex,
        context: ModelContext, report: inout ImportReport
    ) -> ExerciseModel? {
        let name = draft.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            report.problems.append("Skipped an unnamed exercise in workout \"\(workout.title)\".")
            return nil
        }
        let model = ExerciseModel(name: name, isCustom: true)
        context.insert(model)
        index.register(model)
        report.exercisesImported += 1
        report.problems.append(
            "\"\(name)\" wasn't in your library, so it was added as a custom exercise to keep the "
                + "sets logged against it."
        )
        return model
    }

    /// The stall memory as the model stores it — the nested format-2 value or the format-1
    /// string, whichever `resolvedStall` found — re-encoded through the app's DTO.
    nonisolated static func stallJSON(_ state: StallState) -> String {
        guard let data = try? JSONEncoder().encode(StallStateDTO(state)) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    nonisolated static func importBodyMeasurements(
        _ items: [BackupBodyMeasurement], context: ModelContext, report: inout ImportReport
    ) {
        let existingIDs = Set(
            ((try? context.fetch(FetchDescriptor<BodyMeasurementModel>())) ?? []).map(\.id)
        )
        for item in items where !existingIDs.contains(item.id) {
            let model = BodyMeasurementModel(
                id: item.id, date: item.date, bodyweightKg: item.bodyweightKg, source: item.source
            )
            context.insert(model)
            report.bodyMeasurementsImported += 1
        }
    }

    nonisolated static func importEquipmentProfiles(
        _ items: [BackupEquipmentProfile], context: ModelContext, report: inout ImportReport
    ) {
        let existing = (try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        // A restore onto a store with no active profile brings the active one back; a merge into a
        // store that already has one never steals its place. Forcing `false` unconditionally, as
        // this used to, left a freshly-restored phone with no active profile at all.
        var hasActive = existing.contains(where: \.isActive)
        for item in items where !existingIDs.contains(item.id) {
            let shouldActivate = item.isActive && !hasActive
            if shouldActivate { hasActive = true }
            let model = EquipmentProfileModel(
                id: item.id, name: item.name, isActive: shouldActivate, barKg: item.barKg,
                availableEquipment: item.availableEquipment,
                plateStockKg: item.resolvedPlateStock.map(\.weightKg),
                plateCounts: item.resolvedPlateStock.map(\.count),
                collarsKg: item.collarsKg, createdAt: item.createdAt,
                seedKey: item.seedKey, restrictsMachines: item.restrictsMachines ?? false,
                availableMachines: item.availableMachines ?? []
            )
            context.insert(model)
            report.equipmentProfilesImported += 1
        }
    }

    nonisolated static func importPrograms(_ items: [BackupProgram], context: ModelContext) {
        let existingIDs = Set(((try? context.fetch(FetchDescriptor<ProgramModel>())) ?? []).map(\.id))
        let existing = (try? context.fetch(FetchDescriptor<ProgramModel>())) ?? []
        let hasActive = existing.contains(where: \.isActive)
        for item in items where !existingIDs.contains(item.id) {
            // A restore onto an empty store brings the active program back; a merge into a store
            // that already has one never steals its place.
            let model = ProgramModel(
                id: item.id, name: item.name, weeks: item.weeks, startedAt: item.startedAt,
                completedAt: item.completedAt, isActive: item.isActive && !hasActive,
                createdAt: item.createdAt
            )
            model.routineIDs = item.routineIDs
            context.insert(model)
            // `program:` is the whole link; `model.programWeeks` must not also be assigned.
            for week in item.programWeeks {
                context.insert(
                    ProgramWeekModel(id: week.id, index: week.index, kind: week.kind, program: model)
                )
            }
        }
    }

    nonisolated static func importAchievements(_ items: [BackupAchievement], context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AchievementModel>())) ?? []
        let existingIDs = Set(existing.map(\.id))
        let existingKeys = Set(existing.map { "\($0.milestoneID)|\($0.tier)" })
        for item in items
        where !existingIDs.contains(item.id) && !existingKeys.contains("\(item.milestoneID)|\(item.tier)") {
            context.insert(
                AchievementModel(
                    id: item.id, milestoneID: item.milestoneID, tier: item.tier, earnedAt: item.earnedAt,
                    workoutID: item.workoutID
                )
            )
        }
    }

    /// Only fills an empty schedule — an existing one is the user's current plan on this device.
    ///
    /// "Empty" means *no rows or no content*, not just no rows: `ScheduleModel` is created lazily
    /// the first time anything reads the schedule, so merely opening the schedule screen before
    /// restoring used to leave a blank row behind that silently swallowed the backup's schedule.
    nonisolated static func importSchedule(_ item: BackupSchedule?, context: ModelContext) {
        guard let item else { return }
        // Format 2 nests the schedule; format 1 carried the app's own JSON string. Either way
        // the row stores the string the app writes, so a nested value is re-encoded here.
        let json = item.scheduleJSON ?? item.resolvedSchedule.flatMap { schedule in
            (try? JSONEncoder().encode(schedule)).flatMap { String(data: $0, encoding: .utf8) }
        } ?? ""
        let existing = (try? context.fetch(FetchDescriptor<ScheduleModel>())) ?? []
        guard let row = existing.first else {
            context.insert(ScheduleModel(scheduleJSON: json, updatedAt: item.updatedAt))
            return
        }
        guard existing.allSatisfy(isBlank) else { return }
        row.scheduleJSON = json
        row.updatedAt = item.updatedAt
    }

    /// A lazily-created row the user never filled in, or one they emptied again: no JSON, or
    /// JSON with no day entries. An empty `WeeklySchedule` encodes as
    /// `{"dayRoutines":[],"dateOverrides":{}}` — the overrides map is a dictionary, so an
    /// empty dictionary value counts as blank too.
    nonisolated static func isBlank(_ model: ScheduleModel) -> Bool {
        let trimmed = model.scheduleJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" || trimmed == "[]" { return true }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        if let dictionary = object as? [String: Any] {
            return dictionary.values.allSatisfy(isEmptyCollection)
        }
        return (object as? [Any])?.isEmpty ?? false
    }

    nonisolated static func isEmptyCollection(_ value: Any) -> Bool {
        if let array = value as? [Any] { return array.isEmpty }
        if let dictionary = value as? [String: Any] { return dictionary.isEmpty }
        return false
    }
}
