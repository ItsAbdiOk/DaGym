import Foundation
import GymCore
import SwiftData

/// One planned set as drafted by the routine builder, before it becomes a `PlannedSetModel`.
struct PlannedSetDraft {
    var kind: SetKind = .working
    var targetReps: Int?
    var targetRepsHigh: Int?
    var targetWeightKg: Double?
    var targetRPE: Double?
    var targetSeconds: Int?

    init(
        kind: SetKind = .working, targetReps: Int? = nil, targetRepsHigh: Int? = nil,
        targetWeightKg: Double? = nil, targetRPE: Double? = nil, targetSeconds: Int? = nil
    ) {
        self.kind = kind
        self.targetReps = targetReps
        self.targetRepsHigh = targetRepsHigh
        self.targetWeightKg = targetWeightKg
        self.targetRPE = targetRPE
        self.targetSeconds = targetSeconds
    }
}

extension [PlannedSetDraft] {
    /// The kind every set shares, or nil when the sets are mixed (or there are none). Drives
    /// the builder's "every set is a drop set / rest-pause" toggles.
    var uniformKind: SetKind? {
        guard let first = first?.kind, allSatisfy({ $0.kind == first }) else { return nil }
        return first
    }

    /// Stamps `kind` onto every set — targets are kept, only the kind changes.
    mutating func setAllKinds(_ kind: SetKind) {
        for index in indices { self[index].kind = kind }
    }
}

/// One exercise slot as drafted by the routine builder.
struct RoutineExerciseDraft {
    var exerciseID: UUID
    var supersetGroup: Int?
    var restOverrideSeconds: Int?
    var note: String = ""
    var sets: [PlannedSetDraft]
    /// Per-exercise progression rule override; nil defers to the routine's rule.
    var overrideRule: ProgressionRule?
    var trainingMaxKg: Double?
    var excludeFromProgression: Bool = false

    init(
        exerciseID: UUID, supersetGroup: Int? = nil, restOverrideSeconds: Int? = nil,
        note: String = "", sets: [PlannedSetDraft] = [], overrideRule: ProgressionRule? = nil,
        trainingMaxKg: Double? = nil, excludeFromProgression: Bool = false
    ) {
        self.exerciseID = exerciseID
        self.supersetGroup = supersetGroup
        self.restOverrideSeconds = restOverrideSeconds
        self.note = note
        self.sets = sets
        self.overrideRule = overrideRule
        self.trainingMaxKg = trainingMaxKg
        self.excludeFromProgression = excludeFromProgression
    }
}

extension WorkoutStore {
    func routines() -> [RoutineInfo] {
        let descriptor = FetchDescriptor<RoutineModel>(
            predicate: #Predicate { !$0.isArchived && $0.mergedIntoID == nil },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let models = fetch(descriptor)
        return models.map(routineInfo)
    }

    /// Upserts a routine and replaces its exercises/planned sets. Pass `id: nil` to create.
    /// `rule`, when passed, is the source of truth (JSON-encoded onto `progressionRuleJSON`);
    /// `progressionRule`/`repRangeLow`/`repRangeHigh` stay as the legacy display fallback.
    /// `symbolName`/`tint` are left as they are when nil, so callers that don't know about the
    /// glyph (seeder, plan import) never reset a routine the user has already decorated.
    @discardableResult
    func saveRoutine(
        id: UUID?, name: String, notes: String = "", progressionRule: String = "doubleProgression",
        repRangeLow: Int = 6, repRangeHigh: Int = 8, rule: ProgressionRule? = nil,
        symbolName: String? = nil, tint: String? = nil,
        exercises: [RoutineExerciseDraft]
    ) -> RoutineInfo {
        let model = id.flatMap(fetchRoutineModel) ?? insertedRoutine()
        model.name = name
        model.notes = notes
        model.progressionRule = progressionRule
        model.repRangeLow = repRangeLow
        model.repRangeHigh = repRangeHigh
        model.progressionRuleValue = rule?.incrementRejectingNonPositive
        if let symbolName { model.symbolName = symbolName }
        if let tint { model.tint = tint }
        model.updatedAt = Date()
        replaceExercises(exercises, on: model)
        save()
        WidgetSnapshotWriter.refresh(store: self)
        return routineInfo(model)
    }

    /// A deep copy of a routine — exercises, planned sets, rule, per-exercise overrides — under
    /// a fresh id and the next free "X (Copy)" / "X (Copy 2)" name. The engine's stall memory
    /// and `importedFromID` are not copied: the copy starts clean and is the user's own. Nil
    /// when there's no such routine.
    @discardableResult
    func duplicateRoutine(id: UUID) -> RoutineInfo? {
        guard let source = fetchRoutineModel(id: id), let drafts = routineDrafts(id: id)?.drafts else {
            return nil
        }
        let copy = RoutineModel(
            name: copyName(for: source.name), notes: source.notes,
            progressionRule: source.progressionRule, repRangeLow: source.repRangeLow,
            repRangeHigh: source.repRangeHigh, progressionRuleJSON: source.progressionRuleJSON,
            sortOrder: nextRoutineSortOrder(), symbolName: source.symbolName, tint: source.tint
        )
        context.insert(copy)
        copy.exercises = drafts.enumerated().map { index, draft in
            makeRoutineExercise(draft, order: index, routine: copy)
        }
        save()
        WidgetSnapshotWriter.refresh(store: self)
        return routineInfo(copy)
    }

    /// Deletes a routine **and every plan that still points at it** — the weekday schedule,
    /// any date overrides, and every program's `routineIDs`.
    ///
    /// Without this the id survived the routine: the schedule showed a blank planned day,
    /// `nextSession` returned nothing for it, a program cycled onto a day with no routine, and
    /// the routine's calendar events sat in the "DaGym" calendar with nothing left to remove
    /// them. Dropping the schedule ids is also what lets the next calendar sync collect those
    /// events: they become in-window days with nothing planned, which is exactly the case
    /// `CalendarSyncService` deletes.
    func deleteRoutine(id: UUID) {
        guard let model = fetchRoutineModel(id: id) else { return }
        context.delete(model)
        removeRoutineFromSchedule(id: id)
        for program in fetch(FetchDescriptor<ProgramModel>()) where program.routineIDs.contains(id) {
            program.routineIDs = program.routineIDs.filter { $0 != id }
        }
        save()
        WidgetSnapshotWriter.refresh(store: self)
    }

    /// The routine's summary plus its exercises as editable drafts, in the
    /// same order — index-paired, so `drafts[i]` is `info.exercises[i]`.
    /// Used by the routine builder to load a routine back for editing.
    func routineDrafts(id: UUID) -> (info: RoutineInfo, drafts: [RoutineExerciseDraft])? {
        guard let model = fetchRoutineModel(id: id) else { return nil }
        let routineExercises = (model.exercises ?? []).sorted { $0.order < $1.order }
        let exerciseInfos = routineExercises.compactMap { $0.exercise.map { exerciseInfo(for: $0) } }
        let setCount = routineExercises.reduce(0) { $0 + ($1.plannedSets?.count ?? 0) }
        let exerciseSetCounts = routineExercises.map { $0.plannedSets?.count ?? 0 }
        let info = RoutineInfo(
            model: model, exercises: exerciseInfos, setCount: setCount, exerciseSetCounts: exerciseSetCounts
        )
        let drafts = routineExercises.compactMap { routineExercise -> RoutineExerciseDraft? in
            guard let exerciseID = routineExercise.exercise?.id else { return nil }
            let sets = (routineExercise.plannedSets ?? [])
                .sorted { $0.order < $1.order }
                .map(plannedSetDraft)
            return RoutineExerciseDraft(
                exerciseID: exerciseID, supersetGroup: routineExercise.supersetGroup,
                restOverrideSeconds: routineExercise.restOverrideSeconds, note: routineExercise.note,
                sets: sets, overrideRule: routineExercise.overrideRuleValue,
                trainingMaxKg: routineExercise.trainingMaxKg,
                excludeFromProgression: routineExercise.excludeFromProgression
            )
        }
        return (info, drafts)
    }

    private func plannedSetDraft(_ model: PlannedSetModel) -> PlannedSetDraft {
        PlannedSetDraft(
            kind: model.setKind, targetReps: model.targetReps, targetRepsHigh: model.targetRepsHigh,
            targetWeightKg: model.targetWeightKg, targetRPE: model.targetRPE,
            targetSeconds: model.targetSeconds
        )
    }

    private func routineInfo(_ model: RoutineModel) -> RoutineInfo {
        let routineExercises = (model.exercises ?? []).sorted { $0.order < $1.order }
        let exercises = routineExercises.compactMap { $0.exercise.map(ExerciseInfo.init(model:)) }
        let setCount = routineExercises.reduce(0) { $0 + ($1.plannedSets?.count ?? 0) }
        let exerciseSetCounts = routineExercises.map { $0.plannedSets?.count ?? 0 }
        return RoutineInfo(
            model: model, exercises: exercises, setCount: setCount, exerciseSetCounts: exerciseSetCounts
        )
    }

    /// "Push A" → "Push A (Copy)", then "(Copy 2)", "(Copy 3)"… — counted from the base name,
    /// so copying a copy doesn't nest "(Copy) (Copy)". Archived routines hold their names too.
    private func copyName(for name: String) -> String {
        let base = Self.copyBaseName(name)
        let taken = Set(fetch(FetchDescriptor<RoutineModel>()).map(\.name))
        let first = "\(base) (Copy)"
        guard taken.contains(first) else { return first }
        var index = 2
        while taken.contains("\(base) (Copy \(index))") { index += 1 }
        return "\(base) (Copy \(index))"
    }

    private static func copyBaseName(_ name: String) -> String {
        guard name.hasSuffix(")"), let open = name.range(of: " (Copy", options: .backwards) else {
            return name
        }
        let inner = name[open.upperBound..<name.index(before: name.endIndex)]
        let isCounted = inner.hasPrefix(" ") && Int(inner.dropFirst()) != nil
        return inner.isEmpty || isCounted ? String(name[..<open.lowerBound]) : name
    }

    private func nextRoutineSortOrder() -> Int {
        let all = fetch(FetchDescriptor<RoutineModel>())
        return (all.map(\.sortOrder).max() ?? -1) + 1
    }

    private func insertedRoutine() -> RoutineModel {
        let model = RoutineModel()
        context.insert(model)
        return model
    }

    private func replaceExercises(_ drafts: [RoutineExerciseDraft], on routine: RoutineModel) {
        // Carried over by exercise id so editing a routine doesn't burn the stall streak/training
        // max the engine has been building (plan.md §6.5) — exercises are deleted and recreated
        // on every save, so the progression state has to be preserved explicitly.
        var carriedState: [UUID: (stallJSON: String, trainingMaxKg: Double?)] = [:]
        for existing in routine.exercises ?? [] {
            if let exerciseID = existing.exercise?.id {
                carriedState[exerciseID] = (existing.stallJSON, existing.trainingMaxKg)
            }
            context.delete(existing)
        }
        routine.exercises = drafts.enumerated().map { index, draft in
            makeRoutineExercise(draft, order: index, routine: routine, carriedState: carriedState)
        }
    }

    private func makeRoutineExercise(
        _ draft: RoutineExerciseDraft, order: Int, routine: RoutineModel,
        carriedState: [UUID: (stallJSON: String, trainingMaxKg: Double?)] = [:]
    ) -> RoutineExerciseModel {
        let exerciseModel = fetchExerciseModel(id: draft.exerciseID)
        let carried = carriedState[draft.exerciseID]
        let routineExercise = RoutineExerciseModel(
            order: order, supersetGroup: draft.supersetGroup, restOverrideSeconds: draft.restOverrideSeconds,
            note: draft.note, stallJSON: carried?.stallJSON ?? "{}",
            trainingMaxKg: draft.trainingMaxKg ?? carried?.trainingMaxKg,
            excludeFromProgression: draft.excludeFromProgression, exercise: exerciseModel, routine: routine
        )
        routineExercise.overrideRuleValue = draft.overrideRule?.incrementRejectingNonPositive
        context.insert(routineExercise)
        routineExercise.plannedSets = draft.sets.enumerated().map { setIndex, setDraft in
            let plannedSet = PlannedSetModel(
                order: setIndex, kind: setDraft.kind.rawValue, targetReps: setDraft.targetReps,
                targetRepsHigh: setDraft.targetRepsHigh, targetWeightKg: setDraft.targetWeightKg,
                targetRPE: setDraft.targetRPE, targetSeconds: setDraft.targetSeconds,
                routineExercise: routineExercise
            )
            context.insert(plannedSet)
            return plannedSet
        }
        return routineExercise
    }
}
