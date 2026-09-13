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
            title: model.title, subtitle: routine?.name ?? "Backfilled", startedAt: date, exercises: entries
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
            syncSets(entry: entry, into: exerciseModel)
            kept.insert(entry.id)
            existing[entry.id] = exerciseModel
        }
        for (id, exerciseModel) in existing where !kept.contains(id) {
            context.delete(exerciseModel)
        }
        save()
    }

    // MARK: - Building a session from a routine

    private func buildEntries(from routine: RoutineModel?) -> [WorkoutExerciseEntry] {
        guard let routine else { return [] }
        let routineExercises = (routine.exercises ?? []).sorted { $0.order < $1.order }
        return routineExercises.compactMap { routineExercise -> WorkoutExerciseEntry? in
            guard let exerciseModel = routineExercise.exercise else { return nil }
            let info = exerciseInfo(for: exerciseModel)
            let previousSets = lastCompletedSets(exerciseID: exerciseModel.id)
            let plannedSets = (routineExercise.plannedSets ?? []).sorted { $0.order < $1.order }
            let sets = plannedSets.enumerated().map { position, planned in
                autoFilledSet(planned: planned, previous: previousSets, position: position)
            }
            return WorkoutExerciseEntry(
                exercise: info, sets: sets, supersetGroup: routineExercise.supersetGroup,
                note: routineExercise.note.isEmpty ? nil : routineExercise.note
            )
        }
    }

    /// The most recent finished workout's logged sets for this exercise, in position order.
    /// Swap for `GymCore.AutoFill.prescription` once the shared module lands (lead's note).
    private func lastCompletedSets(exerciseID: UUID) -> [SetLogModel] {
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let workouts = (try? context.fetch(descriptor)) ?? []
        for workout in workouts {
            if let match = (workout.exercises ?? []).first(where: { $0.exercise?.id == exerciseID }) {
                return (match.sets ?? []).sorted { $0.order < $1.order }
            }
        }
        return []
    }

    private func autoFilledSet(planned: PlannedSetModel, previous: [SetLogModel], position: Int) -> SetEntry {
        let ghost = previous.indices.contains(position) ? previous[position] : nil
        let weight = ghost?.weightKg ?? planned.targetWeightKg ?? 0
        let reps = ghost?.reps ?? planned.targetReps ?? 0
        let previousLine = ghost.map { "\(WorkoutSession.format($0.weightKg)) × \($0.reps)" }
        return SetEntry(
            kind: planned.setKind, weightKg: weight, reps: reps, previous: previousLine,
            targetSeconds: planned.targetSeconds
        )
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
