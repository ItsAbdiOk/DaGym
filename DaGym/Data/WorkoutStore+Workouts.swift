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
        session.fillPlaceholderWarmups()
        return session
    }

    /// Appends a routine's exercises to a running session, built the same way `startWorkout`
    /// builds them (progression prescriptions, auto-fill, history strip). The session and its
    /// `WorkoutModel` take a combined title ("Push A + Arms") so history shows every routine
    /// that fed the workout. Used by a multi-routine schedule day and the header's
    /// "Add routine to this session".
    func appendRoutine(id: UUID, to session: WorkoutSession) {
        guard let routine = fetchRoutineModel(id: id) else { return }
        session.exercises.append(contentsOf: buildEntries(from: routine))
        session.fillPlaceholderWarmups()
        let title = Self.combinedTitle(session.title, adding: routine.name)
        session.title = title
        session.subtitle = title
        if let workoutID = session.workoutID, let model = fetchWorkoutModel(id: workoutID) {
            model.title = title
            model.routineName = Self.combinedTitle(model.routineName, adding: routine.name)
            if model.routineID == nil { model.routineID = routine.id }
        }
        sync(session: session)
    }

    /// "Push A + Arms": the existing title with `name` joined on, unless it's already there
    /// or the session hasn't been named by a routine yet.
    static func combinedTitle(_ current: String, adding name: String) -> String {
        let placeholders: Set<String> = ["", "Freestyle", "Backfilled workout", "Backfilled"]
        guard !placeholders.contains(current) else { return name }
        let parts = current.components(separatedBy: " + ")
        guard !parts.contains(name) else { return current }
        return current + " + " + name
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

    /// A fresh exercise entry auto-filled from the previous session the same way `startWorkout`
    /// fills a routine's planned sets. Used when adding an exercise mid-workout, where there's
    /// no planned-set template to draw from. The row count is the previous session's completed
    /// working-set count (`setCount` overrides it); three when the exercise was never logged.
    func autoFilledEntry(for exercise: ExerciseInfo, setCount: Int? = nil) -> WorkoutExerciseEntry {
        let workingSet = AutoFillSetSpec(
            kind: .working, targetReps: nil, targetWeightKg: nil, targetSeconds: nil
        )
        let count = setCount ?? previousWorkingSetCount(exerciseID: exercise.id) ?? 3
        let planned = Array(repeating: workingSet, count: max(1, count))
        let sets = autoFilledSets(
            exerciseID: exercise.id, planned: planned, incrementKg: exercise.incrementKg
        )
        return withHistoryStrip(WorkoutExerciseEntry(exercise: exercise, sets: sets))
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
            buildEntry(routine: routine, routineExercise: $0, weekKind: weekKind).map(withHistoryStrip)
        }
    }

    /// Fills the card's "last sessions" strip and e1RM sparkline from finished history — the
    /// two fields every store-built entry shows on `ExerciseCard`.
    func withHistoryStrip(_ entry: WorkoutExerciseEntry) -> WorkoutExerciseEntry {
        var entry = entry
        entry.lastSessions = lastSessions(exerciseID: entry.exercise.id)
        entry.sparkline = sparklineSeries(exerciseID: entry.exercise.id).suffix(8).map(\.1)
        return entry
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

    /// Prescribed by `ProgressionEngine`: the engine's numbers for the working sets, the
    /// previous session's raw values as the ghost (matched the same way `AutoFill` matches them),
    /// and the reason as the "why". Warm-ups are never the engine's business — they take the
    /// plan/previous auto-fill so a 40 kg ramp-up set stays 40 kg when the working weight is 80.
    /// A `.firstTime` prescription (no baseline session yet) carries no numbers of its own, so
    /// the plan's targets fill the row instead of 0 kg — the why card still says it's the first
    /// time. The engine may also prescribe more working sets than the plan (bodyweight "+1 set");
    /// the extras are appended, templated on the last planned working set.
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
        let useGhost = prescribed.reason.kind == .firstTime
        let (rxByPlannedIndex, perPlannedSet) = Self.workingPrescriptions(
            prescribed.sets, plannedSets: plannedSets
        )
        var sets = zip(plannedSets, ghosts).enumerated().map { index, pair -> SetEntry in
            let (plannedSet, ghost) = pair
            let rx = useGhost ? nil : rxByPlannedIndex[index]
            return Self.prescribedSet(
                kind: plannedSet.setKind, rx: rx, ghost: ghost, targetSeconds: plannedSet.targetSeconds,
                reason: prescribed.reason.title
            )
        }
        let workingCount = plannedSets.filter { $0.setKind.countsTowardStats }.count
        if !useGhost, !perPlannedSet, prescribed.sets.count > workingCount,
           let templateIndex = plannedSets.lastIndex(where: { $0.setKind.countsTowardStats }),
           ghosts.indices.contains(templateIndex) {
            let template = plannedSets[templateIndex]
            let ghost = ghosts[templateIndex]
            for rx in prescribed.sets.dropFirst(workingCount) {
                sets.append(Self.prescribedSet(
                    kind: template.setKind, rx: rx, ghost: ghost, targetSeconds: template.targetSeconds,
                    reason: prescribed.reason.title
                ))
            }
        }
        return WorkoutExerciseEntry(
            exercise: info, sets: sets, supersetGroup: routineExercise.supersetGroup,
            note: routineExercise.note.isEmpty ? nil : routineExercise.note,
            whyTitle: prescribed.reason.title, whyBody: prescribed.reason.body,
            whyKind: prescribed.reason.kind
        )
    }

    /// The engine's prescription for each planned-set index, nil for warm-ups. Rules that size
    /// from the working sets alone emit one prescription per working set; older ones emit one
    /// per planned set (warm-ups included) — told apart by count, and paired accordingly. The
    /// flag says which shape was seen, so the caller doesn't mistake warm-up rows for extra sets.
    private static func workingPrescriptions(
        _ prescriptions: [Prescription], plannedSets: [PlannedSetModel]
    ) -> (byPlannedIndex: [Prescription?], perPlannedSet: Bool) {
        let workingIndices = plannedSets.indices.filter { plannedSets[$0].setKind.countsTowardStats }
        let perPlannedSet = prescriptions.count == plannedSets.count
            && workingIndices.count != plannedSets.count
        var result = [Prescription?](repeating: nil, count: plannedSets.count)
        for (position, plannedIndex) in workingIndices.enumerated() {
            let rxIndex = perPlannedSet ? plannedIndex : position
            result[plannedIndex] = prescriptions.indices.contains(rxIndex) ? prescriptions[rxIndex] : nil
        }
        return (result, perPlannedSet)
    }

    /// One row: the engine's numbers when it has them for this set, otherwise the auto-fill
    /// (plan target, or the previous session's matching set); the ghost always comes from the
    /// previous session.
    private static func prescribedSet(
        kind: SetKind, rx: Prescription?, ghost: Prescription, targetSeconds: Int?, reason: String
    ) -> SetEntry {
        let numbers = rx ?? ghost
        return SetEntry(
            kind: kind, weightKg: numbers.weightKg, reps: numbers.reps,
            previousWeightKg: ghost.previous != nil ? ghost.weightKg : nil,
            previousReps: ghost.previous != nil ? ghost.reps : nil,
            durationSeconds: numbers.durationSeconds ?? targetSeconds,
            prescriptionReason: reason, assistanceKg: rx?.assistanceKg
        )
    }

    /// A program's planned deload week: a fraction of the normal sets at a fraction of the last
    /// logged load (`DeloadDetector.deloadPlan`), flagged `wasPlannedDeload` so it's excluded as
    /// the baseline future progression builds from.
    private func deloadEntry(
        info: ExerciseInfo, plannedSets: [PlannedSetModel], routineExercise: RoutineExerciseModel
    ) -> WorkoutExerciseEntry {
        let baseline = exerciseHistory(exerciseID: info.id).first { !$0.wasPlannedDeload }?
            .workingSets.first?.weightKg
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
    /// for `AutoFill`'s "is the plan newer than this?" check. A session with nothing completed,
    /// a planned deload, or one logged under an excluded routine slot is skipped — the next
    /// older one is the previous.
    private func previousSets(exerciseID: UUID) -> (sets: [PreviousSet], date: Date?) {
        guard let previous = previousLoggedExercise(exerciseID: exerciseID) else { return ([], nil) }
        let sets = (previous.exercise.sets ?? []).filter(\.isCompleted).sorted { $0.order < $1.order }
        return (
            sets.map { setModel in
                PreviousSet(
                    kind: setModel.setKind, weightKg: setModel.weightKg, reps: setModel.reps,
                    durationSeconds: setModel.durationSeconds
                )
            },
            previous.workout.startedAt
        )
    }

    /// Completed working-set count from the previous counting session (see `previousSets`);
    /// nil when the exercise was never logged.
    private func previousWorkingSetCount(exerciseID: UUID) -> Int? {
        guard let previous = previousLoggedExercise(exerciseID: exerciseID) else { return nil }
        return (previous.exercise.sets ?? []).filter { $0.isCompleted && $0.setKind.countsTowardStats }.count
    }

    private func previousLoggedExercise(
        exerciseID: UUID
    ) -> (exercise: WorkoutExerciseModel, workout: WorkoutModel)? {
        for workout in finishedWorkoutModelsNewestFirst() {
            let candidates = (workout.exercises ?? []).filter {
                $0.exercise?.id == exerciseID && !$0.wasPlannedDeload && !$0.excludedFromProgression
                    && ($0.sets ?? []).contains(where: \.isCompleted)
            }
            if let match = candidates.min(by: { $0.order < $1.order }) { return (match, workout) }
        }
        return nil
    }

    // MARK: - Syncing

    /// Stamps `excludedFromProgression` from the routine slot the workout was started from, once,
    /// when the row is first persisted — so a later edit to the routine flag leaves this
    /// workout's history as it was logged.
    private func makeWorkoutExercise(
        entry: WorkoutExerciseEntry, workout: WorkoutModel
    ) -> WorkoutExerciseModel {
        let exerciseModel = fetchExerciseModel(id: entry.exercise.id)
        let excluded = workout.routineID.flatMap(fetchRoutineModel)?.exercises?
            .contains { $0.exercise?.id == entry.exercise.id && $0.excludeFromProgression } ?? false
        let model = WorkoutExerciseModel(
            id: entry.id, excludedFromProgression: excluded, exercise: exerciseModel, workout: workout
        )
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
