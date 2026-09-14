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
    ///
    /// `calendar` is the lifter's `Preferences.trainingCalendar`, handed in by the call site the
    /// same way `unit:` is (the store never reads `Preferences`). It decides which week of the
    /// active program today falls in — and so whether this session is a planned deload — so that
    /// a Sunday-start lifter is not given a deload week on a different day from the one the
    /// Programmes screen shows.
    func startWorkout(routineID: UUID?, calendar: Calendar = .current) -> WorkoutSession {
        let routine = routineID.flatMap(fetchRoutineModel)
        let entries = buildEntries(from: routine, calendar: calendar)
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
        if let routine { session.routineGlyphs[routine.id] = Self.routineGlyph(routine) }
        session.fillPlaceholderWarmups()
        return session
    }

    /// `RoutineGlyphInfo` for one routine — shared by `startWorkout`, `appendRoutine`,
    /// `resumeSession(for:)` and `workoutDetail(id:)`.
    static func routineGlyph(_ routine: RoutineModel) -> RoutineGlyphInfo {
        RoutineGlyphInfo(name: routine.name, symbolName: routine.symbolName, tint: routine.tint)
    }

    /// Looks up every distinct `WorkoutExerciseEntry.routineID` among `entries`, falling back to
    /// `.deletedRoutine` for one whose routine no longer exists.
    func routineGlyphs(for entries: [WorkoutExerciseEntry]) -> [UUID: RoutineGlyphInfo] {
        Set(entries.compactMap(\.routineID)).reduce(into: [:]) { result, routineID in
            result[routineID] = fetchRoutineModel(id: routineID).map(Self.routineGlyph) ?? .deletedRoutine
        }
    }

    /// Appends a routine's exercises to a running session, built the same way `startWorkout`
    /// builds them (progression prescriptions, auto-fill, history strip). The session and its
    /// `WorkoutModel` take a combined title ("Push A + Arms") so history shows every routine
    /// that fed the workout. Used by a multi-routine schedule day and the header's
    /// "Add routine to this session".
    func appendRoutine(id: UUID, to session: WorkoutSession, calendar: Calendar = .current) {
        guard let routine = fetchRoutineModel(id: id) else { return }
        session.exercises.append(contentsOf: buildEntries(from: routine, calendar: calendar))
        session.routineGlyphs[routine.id] = Self.routineGlyph(routine)
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

    /// Starts a session logged after the fact ("Log a Past Workout"). The planned end
    /// (`date + durationMinutes`) rides on the *session*, not on the `WorkoutModel`: a workout
    /// with `endedAt` already set is a finished workout everywhere in this app, so stamping it
    /// at the start made a backfill that was never finished a permanent phantom in history — it
    /// counted in lifetime stats, streaks and the widget, it was inside its own progression
    /// baseline while it was still being logged, and it slipped through `finish`'s
    /// double-finish guard. `finish` stamps `endedAt` from `session.backfillEndedAt`, like
    /// every other session.
    func startBackfill(
        date: Date, durationMinutes: Int, routineID: UUID?, calendar: Calendar = .current
    ) -> WorkoutSession {
        let routine = routineID.flatMap(fetchRoutineModel)
        let entries = buildEntries(from: routine, calendar: calendar)
        let model = WorkoutModel(
            title: routine?.name ?? "Backfilled workout", startedAt: date,
            isBackfilled: true, routineID: routine?.id, routineName: routine?.name ?? ""
        )
        context.insert(model)
        save()
        let session = WorkoutSession(
            title: model.title, subtitle: routine?.name ?? "Backfilled", startedAt: date, exercises: entries,
            isBackfilled: true
        )
        session.workoutID = model.id
        session.backfillEndedAt = date.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return session
    }

    /// Writes the session's exercises/sets into the `WorkoutModel` graph, upserting by id.
    /// Cheap enough to call after every mutation.
    func sync(session: WorkoutSession) {
        guard let workoutID = session.workoutID,
              let workout = fetchWorkoutModel(id: workoutID) else { return }
        workout.notes = session.notes
        var existing = Dictionary(uniqueKeysWithValues: (workout.exercises ?? []).map { ($0.id, $0) })
        var kept = Set<UUID>()
        // Resolved once for the whole sync rather than inside `makeWorkoutExercise`: the library
        // models for the rows about to be created come from one batched query, and the routine
        // whose `excludeFromProgression` flags they're stamped from is the workout's own, so it
        // cannot differ between them. Nothing is fetched when no new rows are needed — the
        // common case, since `sync` runs after every set edit.
        let newEntries = session.exercises.filter { existing[$0.id] == nil }
        // Rows whose entry now points at a *different* library exercise than the persisted row
        // does — an in-place swap (`replaceInPlace`) keeps the entry id and changes only
        // `entry.exercise`, so the id lookup above still finds the old row. Without re-pointing
        // it, every set logged after the swap was credited to the exercise that was swapped
        // *out*: history detail, the sparkline, the progression baseline and
        // `rebuildPersonalRecords` all read the model, not the session.
        let swapped = session.exercises.filter { entry in
            guard let model = existing[entry.id] else { return false }
            return model.exercise?.id != entry.exercise.id
        }
        let libraryModels = fetchExerciseModels(
            ids: Set((newEntries + swapped).map(\.exercise.id))
        )
        let sourceRoutine = newEntries.isEmpty ? nil : workout.routineID.flatMap(fetchRoutineModel)
        for (index, entry) in session.exercises.enumerated() {
            let exerciseModel = existing[entry.id] ?? makeWorkoutExercise(
                entry: entry, workout: workout, exercise: libraryModels[entry.exercise.id],
                sourceRoutine: sourceRoutine
            )
            // A missing library row (a deleted exercise) leaves the row pointing where it did:
            // losing the old exercise is worse than the stale one.
            if exerciseModel.exercise?.id != entry.exercise.id,
               let replacement = libraryModels[entry.exercise.id] {
                exerciseModel.exercise = replacement
            }
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
        // One fetch of the finished-workout list for the whole add: the row count, the auto-fill
        // ghost, the last-sessions strip and the sparkline all read from it. Each used to query
        // it separately — four round trips to add one exercise mid-workout.
        let facts = makeSessionFacts(routineID: nil)
        let finished = facts.finishedWorkouts
        let count = setCount ?? previousWorkingSetCount(
            exerciseID: exercise.id, finishedWorkouts: finished
        ) ?? 3
        let planned = Array(repeating: workingSet, count: max(1, count))
        let sets = autoFilledSets(
            exerciseID: exercise.id, planned: planned, incrementKg: exercise.incrementKg,
            finishedWorkouts: finished
        )
        return withHistoryStrip(WorkoutExerciseEntry(exercise: exercise, sets: sets), facts: facts)
    }

    // MARK: - Building a session from a routine

    // One planned set as (kind, target reps, target weight, target seconds) — the shape
    // `GymCore.AutoFill.prescriptions` expects. Named distinctly from `GymCore.PlannedSetSpec`
    // (the progression engine's own type), which this file also uses.
    // swiftlint:disable:next large_tuple
    private typealias AutoFillSetSpec = (
        kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?
    )

    private func buildEntries(
        from routine: RoutineModel?, calendar: Calendar = .current
    ) -> [WorkoutExerciseEntry] {
        guard let routine else { return [] }
        let routineExercises = (routine.exercises ?? []).sorted { $0.order < $1.order }
        // Fetched once for the whole routine: the finished-workout list (progression baseline,
        // ghosts, last-sessions strip, sparkline), the equipment profile, the latest bodyweight,
        // the active program's week/cycle and the PR cache. None of them can differ between the
        // exercises of one session, and re-deriving each per exercise was the N+1 that made
        // `startWorkout` visibly stall on an 8+ exercise routine.
        let facts = makeSessionFacts(routineID: routine.id, calendar: calendar)
        return routineExercises.compactMap { routineExercise in
            buildEntry(routine: routine, routineExercise: routineExercise, facts: facts)
                .map { entry -> WorkoutExerciseEntry in
                    var entry = withHistoryStrip(entry, facts: facts)
                    entry.routineID = routine.id
                    return entry
                }
        }
    }

    /// Fills the card's "last sessions" strip and e1RM sparkline from finished history — the
    /// two fields every store-built entry shows on `ExerciseCard`. Pass `finishedWorkouts`
    /// (newest first) to reuse an already-fetched list instead of querying the store again.
    func withHistoryStrip(
        _ entry: WorkoutExerciseEntry, facts: SessionFacts? = nil
    ) -> WorkoutExerciseEntry {
        var entry = entry
        let finished = facts?.finishedWorkouts
        // The entry's own `ExerciseInfo` already carries the logging style both of these used to
        // re-fetch the `ExerciseModel` for — two queries per exercise, for a value in hand.
        let (id, style) = (entry.exercise.id, entry.exercise.loggingStyle)
        entry.lastSessions = lastSessions(exerciseID: id, finishedWorkouts: finished, style: style)
        entry.sparkline = sparklineSeries(exerciseID: id, finishedWorkouts: finished, style: style)
            .suffix(8).map(\.1)
        return entry
    }

    private func buildEntry(
        routine: RoutineModel, routineExercise: RoutineExerciseModel, facts: SessionFacts
    ) -> WorkoutExerciseEntry? {
        guard let exerciseModel = routineExercise.exercise else { return nil }
        let info = exerciseInfo(for: exerciseModel, facts: facts)
        let plannedSets = (routineExercise.plannedSets ?? []).sorted { $0.order < $1.order }
        if facts.weekKind == .deload, !routineExercise.excludeFromProgression {
            return deloadEntry(
                info: info, plannedSets: plannedSets, routineExercise: routineExercise, facts: facts
            )
        }
        if let prescribed = computeProgression(
            routine: routine, routineExercise: routineExercise, exerciseInfo: info, plannedSets: plannedSets,
            facts: facts
        ) {
            return prescribedEntry(
                info: info, plannedSets: plannedSets, prescribed: prescribed,
                routineExercise: routineExercise, finishedWorkouts: facts.finishedWorkouts
            )
        }
        return autoFillEntry(
            info: info, plannedSets: plannedSets, routineExercise: routineExercise,
            finishedWorkouts: facts.finishedWorkouts
        )
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
        routineExercise: RoutineExerciseModel, finishedWorkouts: [WorkoutModel]
    ) -> WorkoutExerciseEntry {
        let planned = plannedSets.map(Self.autoFillSpec)
        let (previous, previousDate) = previousSets(exerciseID: info.id, finishedWorkouts: finishedWorkouts)
        let ghosts = AutoFill.prescriptions(
            planned: planned, previous: previous, incrementKg: info.incrementKg,
            planUpdatedAt: routineExercise.routine?.updatedAt, previousDate: previousDate
        )
        // A plan target set *after* the session the engine built its baseline from outranks the
        // engine. `AutoFill` already resolves this precedence for the non-engine path ("from your
        // updated plan"); without the same rule here, editing a routine's target weight — or
        // approving the Coach's deload card, which is an automated version of that edit — changed
        // nothing, because the engine reads history and never the plan.
        let planIsNewer = Self.planOverridesPrescription(
            plannedSets: plannedSets, planUpdatedAt: routineExercise.routine?.updatedAt,
            baselineDate: prescribed.previousDate ?? previousDate
        )
        let useGhost = prescribed.reason.kind == .firstTime || planIsNewer
        let reason = planIsNewer ? Self.updatedPlanReason : prescribed.reason
        let (rxByPlannedIndex, perPlannedSet) = Self.workingPrescriptions(
            prescribed.sets, plannedSets: plannedSets
        )
        var sets = zip(plannedSets, ghosts).enumerated().map { index, pair -> SetEntry in
            let (plannedSet, ghost) = pair
            let rx = useGhost ? nil : rxByPlannedIndex[index]
            return Self.prescribedSet(
                kind: plannedSet.setKind, rx: rx, ghost: ghost, targetSeconds: plannedSet.targetSeconds,
                reason: reason.title
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
                    reason: reason.title
                ))
            }
        }
        return WorkoutExerciseEntry(
            exercise: info, sets: sets, supersetGroup: routineExercise.supersetGroup,
            note: routineExercise.note.isEmpty ? nil : routineExercise.note,
            whyTitle: reason.title, whyBody: reason.body, whyKind: reason.kind
        )
    }

    /// The "why" shown when the plan outranks the engine for this session.
    private static let updatedPlanReason = PrescriptionReason(
        title: "From your updated plan",
        body: "Your plan's target weight changed after your last session, so this session uses the "
            + "plan. Progression picks up from what you log today.",
        kind: .plan
    )

    /// True when the plan's working target weight has *changed* since the engine last judged
    /// this lift, and so should win for one session.
    ///
    /// `RoutineModel.updatedAt` alone cannot answer this: `saveRoutine` and
    /// `addExercise(toRoutine:)` stamp it on every save — a rename, a reorder, a superset
    /// change, a glyph, a note — and "some working set has a target weight" is a condition that,
    /// once true, stays true for ever. Together they stranded a weight permanently: approve the
    /// Coach's deload at 80 kg → the plan says 72.5; rebuild to 90 kg over two months through
    /// the engine; rename the routine; next session is prescribed 72.5 kg "From your updated
    /// plan", and `resetIfWeightChanged` then zeroes the miss streak for good measure. Approving
    /// a deload on *one* lift bumped the routine's stamp, so every other lift in that routine
    /// carrying a plan target reverted with it.
    ///
    /// So the stamp is only the cheap first gate; the answer is the number itself, compared
    /// against `StallState.lastPlanTargetWeightKg` — what the plan said the last time
    /// `persistProgression` committed a judgement for this lift. Equal means the save didn't
    /// touch this target, and the engine keeps the floor. Different (or never recorded) means a
    /// real edit, or an approved Coach deload, and the plan wins — exactly once, because
    /// finishing that session records the new number and the two match again.
    ///
    /// The only edit made to this file for the progression/deload review: this function's body
    /// and doc comment. Its signature and its single call site in `prescribedEntry` are
    /// unchanged, and the comparison itself lives in `WorkoutStore+Progression.swift`.
    private static func planOverridesPrescription(
        plannedSets: [PlannedSetModel], planUpdatedAt: Date?, baselineDate: Date?
    ) -> Bool {
        guard let planUpdatedAt, let baselineDate, planUpdatedAt > baselineDate else { return false }
        return planTargetWeightChanged(plannedSets)
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
            // A hold that hasn't happened yet is a *target*, not a duration held — the same
            // split `autoFilledSets` already makes. Filling `durationSeconds` showed a fresh
            // 45-second plank as 45 seconds already held.
            targetSeconds: numbers.durationSeconds ?? targetSeconds,
            prescriptionReason: reason, assistanceKg: rx?.assistanceKg
        )
    }

    /// A program's planned deload week: a fraction of the normal sets at a fraction of the last
    /// logged load (`DeloadDetector.deloadPlan`), flagged `wasPlannedDeload` so it's excluded as
    /// the baseline future progression builds from.
    private func deloadEntry(
        info: ExerciseInfo, plannedSets: [PlannedSetModel], routineExercise: RoutineExerciseModel,
        facts: SessionFacts
    ) -> WorkoutExerciseEntry {
        let baseline = exerciseHistory(exerciseID: info.id, finishedWorkouts: facts.finishedWorkouts)
            .first { !$0.wasPlannedDeload }?.workingSets.first?.weightKg
        let baselineWeight = baseline ?? plannedSets.first?.targetWeightKg ?? 0
        // Sized from the *working* sets. Passing the raw planned count let the warm-ups eat the
        // deload: a routine with 2 warm-ups and 1 working set asked for `deloadPlan(sets: 3)`,
        // which is 2 — and those two, taken by position, were the two warm-ups. A deload week
        // prescribed zero working sets at 90 %.
        let workingSets = plannedSets.filter { $0.setKind.countsTowardStats }
        let plan = DeloadDetector.deloadPlan(sets: max(workingSets.count, 1), load: baselineWeight)
        // An assisted exercise logs the *assistance* dialled in, not the load lifted, so less of
        // it is harder work. Scaling it by the deload fraction handed the lifter a harder set in
        // a deload week; easing off means dialling assistance up by the same fraction instead.
        let fraction = TrainingConstants.deloadLoadFraction
        let loadKg: Double
        if info.loggingStyle == .assisted {
            // `.assisted` rounds on a `.free` grid (see `loadGrid`), so there is nothing to snap to.
            loadKg = fraction > 0 ? baselineWeight / fraction : baselineWeight
        } else {
            loadKg = loadGrid(for: info, equipment: facts.equipment).nearestBelow(plan.loadKg)
        }
        let template = workingSets.first
        let sets = (0..<min(plan.sets, max(workingSets.count, 1))).map { index -> SetEntry in
            let spec = index < workingSets.count ? workingSets[index] : template
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
        info: ExerciseInfo, plannedSets: [PlannedSetModel], routineExercise: RoutineExerciseModel,
        finishedWorkouts: [WorkoutModel]
    ) -> WorkoutExerciseEntry {
        let planned = plannedSets.map(Self.autoFillSpec)
        let sets = autoFilledSets(
            exerciseID: info.id, planned: planned, incrementKg: info.incrementKg,
            planUpdatedAt: routineExercise.routine?.updatedAt, finishedWorkouts: finishedWorkouts
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
        exerciseID: UUID, planned: [AutoFillSetSpec], incrementKg: Double, planUpdatedAt: Date? = nil,
        finishedWorkouts: [WorkoutModel]? = nil
    ) -> [SetEntry] {
        let (previous, previousDate) = previousSets(
            exerciseID: exerciseID, finishedWorkouts: finishedWorkouts
        )
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

    // MARK: - Syncing

    /// Stamps `excludedFromProgression` from the routine slot the workout was started from, once,
    /// when the row is first persisted — so a later edit to the routine flag leaves this
    /// workout's history as it was logged.
    private func makeWorkoutExercise(
        entry: WorkoutExerciseEntry, workout: WorkoutModel, exercise: ExerciseModel?,
        sourceRoutine: RoutineModel?
    ) -> WorkoutExerciseModel {
        let excluded = sourceRoutine?.exercises?
            .contains { $0.exercise?.id == entry.exercise.id && $0.excludeFromProgression } ?? false
        let model = WorkoutExerciseModel(
            id: entry.id, excludedFromProgression: excluded, routineID: entry.routineID,
            exercise: exercise, workout: workout
        )
        context.insert(model)
        // Linked through the `workout:` inverse alone — assigning the parent's array at the same
        // time makes SwiftData rebuild a relationship it is already mid-way through updating,
        // which traps (the same trap `restoreWorkout` was rewritten to avoid).
        return model
    }

    private func syncSets(entry: WorkoutExerciseEntry, into exerciseModel: WorkoutExerciseModel) {
        var existing = Dictionary(uniqueKeysWithValues: (exerciseModel.sets ?? []).map { ($0.id, $0) })
        var kept = Set<UUID>()
        let workout = exerciseModel.workout
        for (index, setEntry) in entry.sets.enumerated() {
            let setModel = existing[setEntry.id] ?? makeSetLog(id: setEntry.id, into: exerciseModel)
            setModel.apply(setEntry, order: index)
            setModel.completedAt = setEntry.isDone
                ? Self.completionDate(setModel.completedAt ?? Date(), in: workout)
                : nil
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
        // Linked through the `workoutExercise:` inverse alone — see `makeWorkoutExercise`.
        return model
    }
}
