import Foundation
import GymCore
import SwiftData

/// Counts and problems from `PlanShareService.importPlan`, shown in `PlanImportPreviewSheet`
/// before the user confirms.
struct PlanImportReport: Equatable {
    var routinesImported = 0
    var routinesSkipped = 0
    var exercisesImported = 0
    var programImported = false
    var problems: [String] = []

    /// "2 routines, 1 custom exercise" for the preview sheet, "Already imported" when a
    /// re-import found nothing new to add.
    var summary: String {
        let parts = [
            countPhrase(routinesImported, singular: "routine"),
            countPhrase(exercisesImported, singular: "custom exercise")
        ].compactMap { $0 }
        var text = parts.isEmpty ? "Already imported" : parts.joined(separator: ", ")
        if programImported { text += " · program" }
        if !problems.isEmpty {
            text += " · \(countPhrase(problems.count, singular: "problem") ?? "")"
        }
        return text
    }

    private func countPhrase(_ count: Int, singular: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

extension PlanShareService {
    /// Merges a decoded `.gymplan` document into `context`. Never overwrites: routines are
    /// matched by `PlanRoutine.id` via `RoutineModel.importedFromID`, so re-importing the same
    /// file twice never duplicates a routine or its program. Custom exercises are matched by
    /// name; an unresolved seedID falls back to creating a custom exercise from the slot's name.
    @discardableResult
    @MainActor
    static func importPlan(
        document: PlanDocument, context: ModelContext, preview: Bool = false
    ) -> PlanImportReport {
        var report = PlanImportReport()
        let exerciseIndex = ExerciseIndex(context: context)
        importExercises(
            document.exercises, index: exerciseIndex, context: context, preview: preview, report: &report
        )
        let routineIDMap = importRoutines(
            document.routines, index: exerciseIndex, context: context, preview: preview, report: &report
        )
        importProgram(
            document.program, routineIDMap: routineIDMap, context: context, preview: preview, report: &report
        )
        if !preview {
            do {
                try context.save()
            } catch {
                report.problems.append("Saving the import failed: \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Looks up `ExerciseModel`s by seedID/name, kept in memory for one import so later routines
    /// can resolve exercises this same import just inserted.
    final class ExerciseIndex {
        private var bySeedID: [String: ExerciseModel] = [:]
        private var byName: [String: ExerciseModel] = [:]

        /// Live rows only, for the reason `BackupService.ExerciseIndex` gives: a seed tombstone
        /// carries its survivor's `seedID`, and resolving a slot onto one hides it from the app.
        init(context: ModelContext) {
            for model in BackupService.liveExercises(context: context) { register(model) }
        }

        func register(_ model: ExerciseModel) {
            byName[model.name.lowercased()] = model
            if let seedID = model.seedID { bySeedID[seedID] = model }
        }

        func find(seedID: String?, name: String) -> ExerciseModel? {
            if let seedID, let model = bySeedID[seedID] { return model }
            return byName[name.lowercased()]
        }
    }

    private static func importExercises(
        _ items: [PlanExercise], index: ExerciseIndex, context: ModelContext, preview: Bool,
        report: inout PlanImportReport
    ) {
        for item in items where index.find(seedID: nil, name: item.name) == nil {
            report.exercisesImported += 1
            let model = ExerciseModel(
                id: UUID(), name: item.name, primaryMuscles: item.primaryMuscles,
                secondaryMuscles: item.secondaryMuscles, equipment: item.equipment,
                mechanic: item.mechanic, loggingStyle: item.loggingStyle, isPerSide: item.isPerSide,
                isCustom: true, barType: item.barType, incrementKg: item.incrementKg,
                restSeconds: item.restSeconds, instructions: item.instructions, notes: item.notes
            )
            // In preview the model is never inserted; it only lets the routine pass below resolve
            // the slots that use it, so the preview reports the same problems the real import will.
            if !preview { context.insert(model) }
            index.register(model)
        }
    }

    /// Imports every routine not already present — matched by `importedFromID`, or by `id` when
    /// the user re-imports a plan they exported themselves. Returns the document routine id →
    /// local `RoutineModel.id` mapping, for `importProgram` — populated for both freshly-created
    /// and already-present routines so a program import still resolves them.
    private static func importRoutines(
        _ items: [PlanRoutine], index: ExerciseIndex, context: ModelContext, preview: Bool,
        report: inout PlanImportReport
    ) -> [UUID: UUID] {
        // Tombstones are matched too — one still stands for a plan the user already imported, so
        // skipping on it avoids re-creating the duplicate its survivor absorbed — but they are
        // indexed *first*, so wherever a tombstone and its survivor share an `importedFromID` the
        // live survivor wins the key and `importProgram` maps the day cycle onto a visible routine.
        let all = (try? context.fetch(FetchDescriptor<RoutineModel>())) ?? []
        let existing = all.filter(\.isMergedAway) + all.filter { !$0.isMergedAway }
        var existingByImportID: [UUID: RoutineModel] = [:]
        for model in existing {
            existingByImportID[model.id] = model
            // A file the user exported from this very device carries the *masked* id (see
            // `PlanShareService.sharedID`), so re-importing your own plan has to match on that too
            // or it would arrive as a duplicate.
            existingByImportID[PlanShareService.sharedID(for: model.id)] = model
            if let importedFromID = model.importedFromID { existingByImportID[importedFromID] = model }
        }
        var idMap: [UUID: UUID] = [:]
        for item in items {
            if let already = existingByImportID[item.id] {
                idMap[item.id] = already.id
                report.routinesSkipped += 1
                continue
            }
            report.routinesImported += 1
            guard !preview else {
                for draft in item.exercises
                where index.find(seedID: draft.exerciseSeedID, name: draft.exerciseName) == nil {
                    report.problems.append(notFoundProblem(draft.exerciseName, routine: item.name))
                }
                continue
            }
            let routine = RoutineModel(
                name: item.name, notes: item.notes, progressionRule: item.progressionRule,
                repRangeLow: item.repRangeLow, repRangeHigh: item.repRangeHigh,
                progressionRuleJSON: item.ruleJSON ?? "", sortOrder: item.sortOrder,
                importedFromID: item.id
            )
            context.insert(routine)
            idMap[item.id] = routine.id
            // Linked through `RoutineExerciseModel.routine` only — assigning `routine.exercises`
            // as well makes SwiftData rebuild a relationship it is already mid-way through
            // updating, the trap `restoreWorkout` was rewritten to avoid.
            for draft in item.exercises {
                _ = makeRoutineExercise(
                    draft, index: index, routine: routine, context: context, report: &report
                )
            }
        }
        return idMap
    }

    private static func makeRoutineExercise(
        _ draft: PlanRoutineExercise, index: ExerciseIndex, routine: RoutineModel, context: ModelContext,
        report: inout PlanImportReport
    ) -> RoutineExerciseModel? {
        guard let exercise = index.find(seedID: draft.exerciseSeedID, name: draft.exerciseName) else {
            report.problems.append(notFoundProblem(draft.exerciseName, routine: routine.name))
            return nil
        }
        let model = RoutineExerciseModel(
            order: draft.order, supersetGroup: draft.supersetGroup,
            restOverrideSeconds: draft.restOverrideSeconds, note: draft.note,
            progressionRuleJSON: draft.ruleJSON, exercise: exercise, routine: routine
        )
        context.insert(model)
        // `routineExercise:` is the whole link; `model.plannedSets` must not also be assigned.
        for set in draft.sets {
            context.insert(PlannedSetModel(
                order: set.order, kind: set.kind, targetReps: set.targetReps,
                targetRepsHigh: set.targetRepsHigh, targetWeightKg: set.targetWeightKg,
                targetRPE: set.targetRPE, targetSeconds: set.targetSeconds,
                targetDistanceMeters: set.targetDistanceMeters, routineExercise: model
            ))
        }
        return model
    }

    private static func notFoundProblem(_ exerciseName: String, routine: String) -> String {
        "Skipped \"\(exerciseName)\" in routine \"\(routine)\": exercise not found."
    }

    /// Imports the program itself, matched by the document's own `PlanProgram.id` reused as the
    /// local `ProgramModel.id` — a re-import with the same id is skipped, same pattern
    /// `BackupService` uses for workouts.
    private static func importProgram(
        _ item: PlanProgram?, routineIDMap: [UUID: UUID], context: ModelContext, preview: Bool,
        report: inout PlanImportReport
    ) {
        guard let item else { return }
        let existingPrograms = (try? context.fetch(FetchDescriptor<ProgramModel>())) ?? []
        let existingIDs = Set(existingPrograms.map(\.id))
            .union(existingPrograms.map { PlanShareService.sharedID(for: $0.id) })
        guard !existingIDs.contains(item.id) else { return }
        report.programImported = true
        guard !preview else { return }
        let model = ProgramModel(id: item.id, name: item.name, weeks: item.weeks)
        model.routineIDs = item.routineIDs.compactMap { routineIDMap[$0] }
        context.insert(model)
        // `program:` is the whole link; `model.programWeeks` must not also be assigned.
        for week in item.programWeeks {
            context.insert(ProgramWeekModel(index: week.index, kind: week.kind, program: model))
        }
    }
}
