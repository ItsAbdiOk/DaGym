import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// Starts a session from a routine (or an empty one when `routineID` is nil). Each planned
    /// exercise is prescribed by `GymCore.ProgressionEngine` (plan.md §6.5) when a progression
    /// rule is active for it; an exercise with no rule (routine or override), or one excluded
    /// from progression, falls back to plain auto-fill by set position from the previous
    /// session (plan.md §6.1). Immediately persists a `WorkoutModel` so a crash mid-workout
    /// never loses it.
    func startWorkout(routineID: UUID?) -> WorkoutSession {
        let routine = routineID.flatMap(fetchRoutineModel)
        let entries = buildEntries(from: routine)
        let model = WorkoutModel(
            title: routine?.name ?? "Freestyle", startedAt: Date(), routineID: routine?.id,
            routineName: routine?.name ?? ""
        )
        context.insert(model)
        save()
        let session = WorkoutSession(
            title: model.title, subtitle: routine?.name ?? "Freestyle", startedAt: model.startedAt,
            exercises: entries
        )
        session.workoutID = model.id
        return session
    }

    func startFreestyle() -> WorkoutSession {
        let model = WorkoutModel(title: "Freestyle", startedAt: Date())
        context.insert(model)
        save()
        let session = WorkoutSession(
            title: "Freestyle", subtitle: "", startedAt: model.startedAt, exercises: []
        )
        session.workoutID = model.id
        return session
    }

    func startBackfill(date: Date, durationMinutes: Int, routineID: UUID?) -> WorkoutSession {
        let routine = routineID.flatMap(fetchRoutineModel)
        let entries = buildEntries(from: routine)
        let endedAt = date.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let model = WorkoutModel(
            title: routine?.name ?? "Backfilled workout", startedAt: date, endedAt: endedAt,
            isBackfilled: true, routineID: routine?.id, routineName: routine?.name ?? ""
        )
        context.insert(model)
        save()
        let session = WorkoutSession(
            title: model.title, subtitle: routine?.name ?? "Backfilled", startedAt: date, exercises: entries,
            isBackfilled: true
        )
        session.workoutID = model.id
        return session
    }

    /// Writes the session's exercises/sets into the `WorkoutModel` graph, upserting by id.
    /// Cheap enough to call after every mutation.
    func sync(session: WorkoutSession) {
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID) else {
            return
        }
        workout.notes = session.notes
        var existing = Dictionary(uniqueKeysWithValues: (workout.exercises ?? []).map { ($0.id, $0) })
        var kept = Set<UUID>()
        for (index, entry) in session.exercises.enumerated() {
            let exerciseModel = existing[entry.id] ?? makeWorkoutExercise(entry: entry, workout: workout)
            exerciseModel.order = index
            exerciseModel.supersetGroup = entry.supersetGroup
            exerciseModel.note = entry.note ?? ""
            exerciseModel.wasSubstitution = entry.wasSubstitution
            exerciseModel.wasPlannedDeload = entry.wasPlannedDeload
            syncSets(entry: entry, into: exerciseModel)
            kept.insert(entry.id)
            existing[entry.id] = exerciseModel
        }
        for (id, exerciseModel) in existing where !kept.contains(id) {
            context.delete(exerciseModel)
        }
        save()
    }

    /// Discards an in-progress session, deleting its backing `WorkoutModel` (and, by cascade,
    /// every exercise/set logged so far). Used by the Active Workout screen's "Discard workout"
    /// confirmation.
    func discard(session: WorkoutSession) {
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID) else {
            return
        }
        context.delete(workout)
        save()
    }

    /// A fresh exercise entry with three working sets, auto-filled from the previous session the
    /// same way `startWorkout` fills a routine's planned sets. Used when adding an exercise
    /// mid-workout, where there's no planned-set template to draw from.
    func autoFilledEntry(for exercise: ExerciseInfo) -> WorkoutExerciseEntry {
        let workingSet = AutoFillSetSpec(
            kind: .working, targetReps: nil, targetWeightKg: nil, targetSeconds: nil
        )
        let planned = Array(repeating: workingSet, count: 3)
        let sets = autoFilledSets(
            exerciseID: exercise.id, planned: planned, incrementKg: exercise.incrementKg
        )
        return WorkoutExerciseEntry(exercise: exercise, sets: sets)
    }

    // MARK: - Building a session from a routine

    // One planned set as (kind, target reps, target weight, target seconds) — the shape
    // `GymCore.AutoFill.prescriptions` expects. Named distinctly from `GymCore.PlannedSetSpec`
    // (the progression engine's own type), which this file also uses.
    // swiftlint:disable:next large_tuple
    private typealias AutoFillSetSpec = (
        kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?
    )

    private func buildEntries(from routine: RoutineModel?) -> [WorkoutExerciseEntry] {
        guard let routine else { return [] }
        let routineExercises = (routine.exercises ?? []).sorted { $0.order < $1.order }
        let weekKind = currentWeekKind(forRoutineID: routine.id)
        return routineExercises.compactMap {
            buildEntry(routine: routine, routineExercise: $0, weekKind: weekKind)
        }
    }

    private func buildEntry(
        routine: RoutineModel, routineExercise: RoutineExerciseModel, weekKind: ProgramWeekKind?
    ) -> WorkoutExerciseEntry? {
        guard let exerciseModel = routineExercise.exercise else { return nil }
        let info = exerciseInfo(for: exerciseModel)
        let plannedSets = (routineExercise.plannedSets ?? []).sorted { $0.order < $1.order }
        if weekKind == .deload, !routineExercise.excludeFromProgression {
            return deloadEntry(info: info, plannedSets: plannedSets, routineExercise: routineExercise)
        }
        if let prescribed = computeProgression(
            routine: routine, routineExercise: routineExercise, exerciseInfo: info, plannedSets: plannedSets
        ) {
            return prescribedEntry(
                info: info, plannedSets: plannedSets, prescribed: prescribed, routineExercise: routineExercise
            )
        }
        return autoFillEntry(info: info, plannedSets: plannedSets, routineExercise: routineExercise)
    }

    /// Prescribed by `ProgressionEngine`: the engine's numbers, the previous session's raw values
    /// as the ghost (matched the same way `AutoFill` matches them), and the reason as the "why".
    /// A `.firstTime` prescription (no baseline session yet) carries no numbers of its own, so the
    /// plan's targets fill the row instead of 0 kg — the why card still says it's the first time.
    private func prescribedEntry(
        info: ExerciseInfo, plannedSets: [PlannedSetModel], prescribed: Prescribed,
        routineExercise: RoutineExerciseModel
    ) -> WorkoutExerciseEntry {
        let planned = plannedSets.map(Self.autoFillSpec)
        let (previous, previousDate) = previousSets(exerciseID: info.id)
        let ghosts = AutoFill.prescriptions(
            planned: planned, previous: previous, incrementKg: info.incrementKg,
            planUpdatedAt: routineExercise.routine?.updatedAt, previousDate: previousDate
        )
        let isFirstTime = prescribed.reason.kind == .firstTime
        let sets = zip(plannedSets, zip(prescribed.sets, ghosts)).map { plannedSet, pair -> SetEntry in
            let (rx, ghost) = pair
            let numbers = isFirstTime ? ghost : rx
            return SetEntry(
                kind: plannedSet.setKind, weightKg: numbers.weightKg, reps: numbers.reps,
                previousWeightKg: ghost.previous != nil ? ghost.weightKg : nil,
                previousReps: ghost.previous != nil ? ghost.reps : nil,
                durationSeconds: numbers.durationSeconds ?? plannedSet.targetSeconds,
                prescriptionReason: prescribed.reason.title, assistanceKg: rx.assistanceKg
            )
        }
        return WorkoutExerciseEntry(
            exercise: info, sets: sets, supersetGroup: routineExercise.supersetGroup,
            note: routineExercise.note.isEmpty ? nil : routineExercise.note,
            whyTitle: prescribed.reason.title, whyBody: prescribed.reason.body,
            whyKind: prescribed.reason.kind
        )
    }

    /// A program's planned deload week: a fraction of the normal sets at a fraction of the last
    /// logged load (`DeloadDetector.deloadPlan`), flagged `wasPlannedDeload` so it's excluded as
    /// the baseline future progression builds from.
    private func deloadEntry(
        info: ExerciseInfo, plannedSets: [PlannedSetModel], routineExercise: RoutineExerciseModel
    ) -> WorkoutExerciseEntry {
        let baseline = exerciseHistory(exerciseID: info.id, limit: 1).first?.workingSets.first?.weightKg
        let baselineWeight = baseline ?? plannedSets.first?.targetWeightKg ?? 0
        let plan = DeloadDetector.deloadPlan(sets: max(plannedSets.count, 1), load: baselineWeight)
        let equipment = activeEquipment()
        let loadKg = loadGrid(for: info, equipment: equipment).nearestBelow(plan.loadKg)
        let template = plannedSets.first
        let sets = (0..<min(plan.sets, max(plannedSets.count, 1))).map { index -> SetEntry in
            let spec = index < plannedSets.count ? plannedSets[index] : template
            return SetEntry(
                kind: spec?.setKind ?? .working, weightKg: loadKg, reps: spec?.targetReps ?? 5,
                durationSeconds: spec?.targetSeconds, prescriptionReason: "Planned deload"
            )
        }
        return WorkoutExerciseEntry(
            exercise: info, sets: sets, supersetGroup: routineExercise.supersetGroup,
            note: routineExercise.note.isEmpty ? nil : routineExercise.note,
            whyTitle: "Planned deload",
            whyBody: "This week is a planned deload — lighter sets and load this session.",
            whyKind: .deload,
            wasPlannedDeload: true
        )
    }

    /// The plain previous-session auto-fill, unaffected by the progression engine — used when an
    /// exercise is excluded from progression.
    private func autoFillEntry(
        info: ExerciseInfo, plannedSets: [PlannedSetModel], routineExercise: RoutineExerciseModel
    ) -> WorkoutExerciseEntry {
        let planned = plannedSets.map(Self.autoFillSpec)
        let sets = autoFilledSets(
            exerciseID: info.id, planned: planned, incrementKg: info.incrementKg,
            planUpdatedAt: routineExercise.routine?.updatedAt
        )
        return WorkoutExerciseEntry(
            exercise: info, sets: sets, supersetGroup: routineExercise.supersetGroup,
            note: routineExercise.note.isEmpty ? nil : routineExercise.note
        )
    }

    private static func autoFillSpec(_ model: PlannedSetModel) -> AutoFillSetSpec {
        (kind: model.setKind, targetReps: model.targetReps, targetWeightKg: model.targetWeightKg,
         targetSeconds: model.targetSeconds)
    }

    /// Pre-fills a run of planned sets from the previous session, matched by position within
    /// each set kind (`GymCore.AutoFill`). Shared by `autoFillEntry` (excluded routine exercises)
    /// and `autoFilledEntry` (a freshly added exercise's default three working sets).
    private func autoFilledSets(
        exerciseID: UUID, planned: [AutoFillSetSpec], incrementKg: Double, planUpdatedAt: Date? = nil
    ) -> [SetEntry] {
        let (previous, previousDate) = previousSets(exerciseID: exerciseID)
        let prescriptions = AutoFill.prescriptions(
            planned: planned, previous: previous, incrementKg: incrementKg,
            planUpdatedAt: planUpdatedAt, previousDate: previousDate
        )
        return zip(planned, prescriptions).map { plan, rx in
            // `rx.previous` is non-nil exactly when `rx.weightKg`/`rx.reps` came from a
            // matched previous set (see `AutoFill.prescription(for:matching:)`) rather than
            // a plan target — that's the only case the ghost should show raw previous data.
            SetEntry(
                kind: plan.kind, weightKg: rx.weightKg, reps: rx.reps,
                previousWeightKg: rx.previous != nil ? rx.weightKg : nil,
                previousReps: rx.previous != nil ? rx.reps : nil,
                targetSeconds: rx.durationSeconds ?? plan.targetSeconds
            )
        }
    }

    /// The most recent finished workout's logged, *completed* sets for this exercise (A6: an
    /// uncompleted "0 × 0" row is not a previous), in position order, plus that session's date
    /// for `AutoFill`'s "is the plan newer than this?" check.
    private func previousSets(exerciseID: UUID) -> (sets: [PreviousSet], date: Date?) {
        for workout in finishedWorkoutModelsNewestFirst() {
            guard let match = (workout.exercises ?? []).first(where: { $0.exercise?.id == exerciseID }) else {
                continue
            }
            let sets = (match.sets ?? []).filter(\.isCompleted).sorted { $0.order < $1.order }
            return (
                sets.map { setModel in
                    PreviousSet(
                        kind: setModel.setKind, weightKg: setModel.weightKg, reps: setModel.reps,
                        durationSeconds: setModel.durationSeconds
                    )
                },
                workout.startedAt
            )
        }
        return ([], nil)
    }

    // MARK: - Syncing

    private func makeWorkoutExercise(
        entry: WorkoutExerciseEntry, workout: WorkoutModel
    ) -> WorkoutExerciseModel {
        let exerciseModel = fetchExerciseModel(id: entry.exercise.id)
        let model = WorkoutExerciseModel(id: entry.id, exercise: exerciseModel, workout: workout)
        context.insert(model)
        workout.exercises = (workout.exercises ?? []) + [model]
        return model
    }

    private func syncSets(entry: WorkoutExerciseEntry, into exerciseModel: WorkoutExerciseModel) {
        var existing = Dictionary(uniqueKeysWithValues: (exerciseModel.sets ?? []).map { ($0.id, $0) })
        var kept = Set<UUID>()
        for (index, setEntry) in entry.sets.enumerated() {
            let setModel = existing[setEntry.id] ?? makeSetLog(id: setEntry.id, into: exerciseModel)
            setModel.apply(setEntry, order: index)
            setModel.completedAt = setEntry.isDone ? (setModel.completedAt ?? Date()) : nil
            kept.insert(setEntry.id)
            existing[setEntry.id] = setModel
        }
        for (id, setModel) in existing where !kept.contains(id) {
            context.delete(setModel)
        }
    }

    private func makeSetLog(id: UUID, into exerciseModel: WorkoutExerciseModel) -> SetLogModel {
        let model = SetLogModel(id: id, workoutExercise: exerciseModel)
        context.insert(model)
        exerciseModel.sets = (exerciseModel.sets ?? []) + [model]
        return model
    }
}
