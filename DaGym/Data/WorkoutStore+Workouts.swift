import Foundation
import GymCore
import SwiftData

extension WorkoutStore {
    /// Starts a session from a routine (or an empty one when `routineID` is nil), auto-filling
    /// each set from the most recent completed workout of the same exercise, and immediately
    /// persists a `WorkoutModel` so a crash mid-workout never loses the session.
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
        var existing = Dictionary(uniqueKeysWithValues: (workout.exercises ?? []).map { ($0.id, $0) })
        var kept = Set<UUID>()
        for (index, entry) in session.exercises.enumerated() {
            let exerciseModel = existing[entry.id] ?? makeWorkoutExercise(entry: entry, workout: workout)
            exerciseModel.order = index
            exerciseModel.supersetGroup = entry.supersetGroup
            exerciseModel.note = entry.note ?? ""
            exerciseModel.wasSubstitution = entry.wasSubstitution
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
        let workingSet = PlannedSetSpec(
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
    // `GymCore.AutoFill.prescriptions` expects.
    // swiftlint:disable:next large_tuple
    private typealias PlannedSetSpec = (
        kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?
    )

    private func buildEntries(from routine: RoutineModel?) -> [WorkoutExerciseEntry] {
        guard let routine else { return [] }
        let routineExercises = (routine.exercises ?? []).sorted { $0.order < $1.order }
        return routineExercises.compactMap { routineExercise -> WorkoutExerciseEntry? in
            guard let exerciseModel = routineExercise.exercise else { return nil }
            let info = exerciseInfo(for: exerciseModel)
            let plannedSets = (routineExercise.plannedSets ?? []).sorted { $0.order < $1.order }
            let planned: [PlannedSetSpec] = plannedSets.map {
                (kind: $0.setKind, targetReps: $0.targetReps, targetWeightKg: $0.targetWeightKg,
                 targetSeconds: $0.targetSeconds)
            }
            let sets = autoFilledSets(
                exerciseID: exerciseModel.id, planned: planned, incrementKg: info.incrementKg
            )
            return WorkoutExerciseEntry(
                exercise: info, sets: sets, supersetGroup: routineExercise.supersetGroup,
                note: routineExercise.note.isEmpty ? nil : routineExercise.note
            )
        }
    }

    /// Pre-fills a run of planned sets from the previous session, matched by position within
    /// each set kind (`GymCore.AutoFill`). Shared by `buildEntries` (routine sets) and
    /// `autoFilledEntry` (a freshly added exercise's default three working sets).
    private func autoFilledSets(
        exerciseID: UUID, planned: [PlannedSetSpec], incrementKg: Double
    ) -> [SetEntry] {
        let prescriptions = AutoFill.prescriptions(
            planned: planned, previous: previousSets(exerciseID: exerciseID), incrementKg: incrementKg
        )
        return zip(planned, prescriptions).map { plan, rx in
            SetEntry(
                kind: plan.kind, weightKg: rx.weightKg, reps: rx.reps, previous: rx.previous,
                targetSeconds: rx.durationSeconds ?? plan.targetSeconds
            )
        }
    }

    /// The most recent finished workout's logged sets for this exercise, in position order.
    private func previousSets(exerciseID: UUID) -> [PreviousSet] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let workouts = (try? context.fetch(descriptor)) ?? []
        for workout in workouts {
            guard let match = (workout.exercises ?? []).first(where: { $0.exercise?.id == exerciseID }) else {
                continue
            }
            let sets = (match.sets ?? []).sorted { $0.order < $1.order }
            return sets.map { setModel in
                PreviousSet(
                    kind: setModel.setKind, weightKg: setModel.weightKg, reps: setModel.reps,
                    durationSeconds: setModel.durationSeconds
                )
            }
        }
        return []
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
