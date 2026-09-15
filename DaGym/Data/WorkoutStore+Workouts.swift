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
        let state = storeSignposter.beginInterval("sync")
        defer { storeSignposter.endInterval("sync", state) }
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
        saveSession()
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
        if exercise.loggingStyle == .cardio {
            let entry = cardioAddedEntry(for: exercise, setCount: setCount, facts: facts)
            return withHistoryStrip(entry, facts: facts)
        }
        let planned = Array(repeating: workingSet, count: max(1, count))
        let sets = autoFilledSets(
            exerciseID: exercise.id, planned: planned, incrementKg: exercise.incrementKg,
            finishedWorkouts: finished
        )
        return withHistoryStrip(WorkoutExerciseEntry(exercise: exercise, sets: sets), facts: facts)
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
