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

/// One exercise slot as drafted by the routine builder.
struct RoutineExerciseDraft {
    var exerciseID: UUID
    var supersetGroup: Int?
    var restOverrideSeconds: Int?
    var note: String = ""
    var sets: [PlannedSetDraft]

    init(
        exerciseID: UUID, supersetGroup: Int? = nil, restOverrideSeconds: Int? = nil,
        note: String = "", sets: [PlannedSetDraft] = []
    ) {
        self.exerciseID = exerciseID
        self.supersetGroup = supersetGroup
        self.restOverrideSeconds = restOverrideSeconds
        self.note = note
        self.sets = sets
    }
}

extension WorkoutStore {
    func routines() -> [RoutineInfo] {
        let descriptor = FetchDescriptor<RoutineModel>(
            predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortOrder)]
        )
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(routineInfo)
    }

    /// Upserts a routine and replaces its exercises/planned sets. Pass `id: nil` to create.
    @discardableResult
    func saveRoutine(
        id: UUID?, name: String, notes: String = "", progressionRule: String = "doubleProgression",
        repRangeLow: Int = 6, repRangeHigh: Int = 8, exercises: [RoutineExerciseDraft]
    ) -> RoutineInfo {
        let model = id.flatMap(fetchRoutineModel) ?? insertedRoutine()
        model.name = name
        model.notes = notes
        model.progressionRule = progressionRule
        model.repRangeLow = repRangeLow
        model.repRangeHigh = repRangeHigh
        model.updatedAt = Date()
        replaceExercises(exercises, on: model)
        save()
        WidgetSnapshotWriter.refresh(store: self)
        return routineInfo(model)
    }

    func deleteRoutine(id: UUID) {
        guard let model = fetchRoutineModel(id: id) else { return }
        context.delete(model)
        save()
        WidgetSnapshotWriter.refresh(store: self)
    }

    /// The routine's summary plus its exercises as editable drafts, in the
    /// same order — index-paired, so `drafts[i]` is `info.exercises[i]`.
    /// Used by the routine builder to load a routine back for editing.
    func routineDrafts(id: UUID) -> (info: RoutineInfo, drafts: [RoutineExerciseDraft])? {
        guard let model = fetchRoutineModel(id: id) else { return nil }
        let routineExercises = (model.exercises ?? []).sorted { $0.order < $1.order }
        let exerciseInfos = routineExercises.compactMap { $0.exercise.map(exerciseInfo(for:)) }
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
                sets: sets
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

    private func insertedRoutine() -> RoutineModel {
        let model = RoutineModel()
        context.insert(model)
        return model
    }

    private func replaceExercises(_ drafts: [RoutineExerciseDraft], on routine: RoutineModel) {
        for existing in routine.exercises ?? [] { context.delete(existing) }
        routine.exercises = drafts.enumerated().map { index, draft in
            makeRoutineExercise(draft, order: index, routine: routine)
        }
    }

    private func makeRoutineExercise(
        _ draft: RoutineExerciseDraft, order: Int, routine: RoutineModel
    ) -> RoutineExerciseModel {
        let exerciseModel = fetchExerciseModel(id: draft.exerciseID)
        let routineExercise = RoutineExerciseModel(
            order: order, supersetGroup: draft.supersetGroup, restOverrideSeconds: draft.restOverrideSeconds,
            note: draft.note, exercise: exerciseModel, routine: routine
        )
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
