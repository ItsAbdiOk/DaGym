import Foundation
import GymCore
import SwiftData

/// Deleting a finished workout and putting it back (the undo toast), with the PR cache and the
/// progression engine's memory re-derived from what remains either way.
extension WorkoutStore {
    /// Deletes a workout and its sets, then rebuilds the PR cache and event log from what
    /// remains — so a mis-typed record dies with the workout that set it. Returns a snapshot
    /// that `restoreWorkout(_:)` re-inserts with the same ids, for an undo toast.
    @discardableResult
    func deleteWorkout(id: UUID) -> DeletedWorkout? {
        guard let model = fetchWorkoutModel(id: id) else {
            // Not in the main store: it may be an Apple Health import, which lives in the local
            // Health store and leaves a tombstone behind so it is never re-imported.
            return deleteImportedHealthWorkout(id: id).map(DeletedWorkout.init(imported:))
        }
        var snapshot = DeletedWorkout(model: model)
        let wasFinished = model.endedAt != nil
        // Captured before the delete: the routine slots whose engine memory this workout fed,
        // and the milestone tiers it earned.
        let slots = Self.progressionSlots(of: model)
        let achievements = achievementModels(forWorkoutID: id)
        snapshot.achievements = achievements.map(DeletedWorkout.Achievement.init)
        // A workout DaGym wrote to Apple Health should not outlive itself there.
        if let healthKitID = model.healthKitID {
            onWorkoutDeletedFromHealth?(healthKitID)
        }
        // A mistyped session that earned a badge left it earned for ever — and `earnedTiers`
        // then blocked the lifter from earning that same tier legitimately later.
        achievements.forEach(context.delete)
        context.delete(model)
        save()
        if wasFinished {
            rebuildPersonalRecords()
            replayProgression(slots: slots)
            save()
        }
        return snapshot
    }

    /// The `(routine, exercise)` pairs a workout's rows were logged under — the routine slots
    /// whose `stallJSON`/`trainingMaxKg` this workout's judgement was folded into.
    private static func progressionSlots(of workout: WorkoutModel) -> [ProgressionSlot] {
        (workout.exercises ?? []).compactMap { exerciseModel in
            guard !exerciseModel.excludedFromProgression,
                  let routineID = exerciseModel.routineID ?? workout.routineID,
                  let exerciseID = exerciseModel.exercise?.id else { return nil }
            return ProgressionSlot(routineID: routineID, exerciseID: exerciseID)
        }
    }

    /// Re-derives each slot's engine memory from the history that is actually there now.
    ///
    /// Deleting a workout reverted its PRs but not its stall state, so a session deleted because
    /// it was mistyped left `consecutiveMisses` elevated and the *next* session could be deloaded
    /// on evidence the lifter had removed. The state is a fold over history, so the only honest
    /// way back is to fold it again: replay the judgement `finish` makes, session by session,
    /// over what remains. `restoreWorkout` runs the same replay, which is what makes undo exact.
    ///
    /// The training max and its cycle marker are carried over rather than replayed — the lifter
    /// set the TM, and the engine only bumps it once per cycle, so re-deriving it would either
    /// lose it or bump it twice.
    private func replayProgression(slots: [ProgressionSlot]) {
        let all = finishedWorkoutModelsNewestFirst()
        for slot in Set(slots) {
            guard let routine = fetchRoutineModel(id: slot.routineID),
                  let routineExercise = (routine.exercises ?? [])
                      .first(where: { $0.exercise?.id == slot.exerciseID }),
                  let exerciseModel = routineExercise.exercise,
                  let plannedSets = routineExercise.plannedSets else { continue }
            var facts = makeSessionFacts(routineID: routine.id, finishedWorkouts: all)
            let info = exerciseInfo(for: exerciseModel, facts: facts)
            let judged = all.indices.filter { Self.isJudged(all[$0], exerciseID: slot.exerciseID) }
            var state = StallState(trainingMaxCycle: routineExercise.stallStateValue.trainingMaxCycle)
            // Oldest first, and only as far back as the engine's own history window reaches.
            for index in judged.prefix(Self.progressionReplayLimit).reversed() {
                routineExercise.stallStateValue = state
                // Exactly what `finish` sees: this session is still *outside* its own baseline.
                facts.finishedWorkouts = Array(all.dropFirst(index + 1))
                guard let result = computeProgression(
                    routine: routine, routineExercise: routineExercise, exerciseInfo: info,
                    plannedSets: plannedSets, facts: facts
                ) else { break }
                state = result.stall
            }
            routineExercise.stallStateValue = state
        }
    }

    /// Whether this workout's row for `exerciseID` is one the engine would ever judge — the same
    /// test `exerciseHistory` and `persistProgression` apply.
    private static func isJudged(_ workout: WorkoutModel, exerciseID: UUID) -> Bool {
        guard let match = (workout.exercises ?? []).first(where: { $0.exercise?.id == exerciseID })
        else { return false }
        return !match.excludedFromProgression && !match.wasPlannedDeload
            && (match.sets ?? []).contains(where: \.isCompleted)
    }

    /// Matches `exerciseHistory`'s own `limit`: further back than this the engine cannot see, so
    /// replaying further cannot change the answer.
    private static let progressionReplayLimit = 6

    private func achievementModels(forWorkoutID id: UUID) -> [AchievementModel] {
        let predicate = #Predicate<AchievementModel> { $0.workoutID == id }
        return fetch(FetchDescriptor(predicate: predicate))
    }

    /// Puts a deleted workout back exactly as it was (same ids, sets and flags) and rebuilds
    /// the PR cache. A no-op if a workout with that id already exists again.
    func restoreWorkout(_ snapshot: DeletedWorkout) {
        if let imported = snapshot.importedHealthWorkout {
            restoreImportedHealthWorkout(imported)
            return
        }
        guard fetchWorkoutModel(id: snapshot.id) == nil else { return }
        let workout = WorkoutModel(
            id: snapshot.id, title: snapshot.title, startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt, notes: snapshot.notes, isBackfilled: snapshot.isBackfilled,
            routineID: snapshot.routineID, routineName: snapshot.routineName,
            bodyweightKg: snapshot.bodyweightKg, sourceDevice: snapshot.sourceDevice,
            // Deliberately not `snapshot.healthKitID`: deleting the workout also deleted the
            // `HKWorkout` DaGym had written for it, so the restored workout has nothing in Health
            // yet. Clearing it lets the finished-workout hook below write a fresh one.
            healthKitID: nil
        )
        context.insert(workout)
        // Children are linked through the `workout:`/`workoutExercise:` inverses only — assigning
        // the parent's array at the same time makes SwiftData rebuild a relationship it is already
        // mid-way through updating, which traps.
        for exercise in snapshot.exercises {
            let exerciseModel = WorkoutExerciseModel(
                id: exercise.id, order: exercise.order, supersetGroup: exercise.supersetGroup,
                note: exercise.note, wasSubstitution: exercise.wasSubstitution,
                wasPlannedDeload: exercise.wasPlannedDeload,
                excludedFromProgression: exercise.excludedFromProgression, routineID: exercise.routineID,
                exercise: exercise.exerciseID.flatMap(fetchExerciseModel), workout: workout
            )
            context.insert(exerciseModel)
            for set in exercise.sets {
                let setModel = SetLogModel(
                    id: set.id, order: set.order, kind: set.kind, weightKg: set.weightKg, reps: set.reps,
                    durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters,
                    inclinePercent: set.inclinePercent, assistanceKg: set.assistanceKg, rpe: set.rpe,
                    isCompleted: set.isCompleted, completedAt: set.completedAt,
                    prescriptionReason: set.prescriptionReason, workoutExercise: exerciseModel
                )
                context.insert(setModel)
            }
        }
        for achievement in snapshot.achievements {
            context.insert(AchievementModel(
                id: achievement.id, milestoneID: achievement.milestoneID, tier: achievement.tier,
                earnedAt: achievement.earnedAt, workoutID: snapshot.id
            ))
        }
        save()
        if snapshot.endedAt != nil {
            // Re-stamped from the rows just inserted (after the save, once the inverses have
            // linked them), the way `finish` stamped them the first time.
            workout.stampTotals()
            rebuildPersonalRecords()
            // The delete replayed this workout out of the engine's memory; put it back the same
            // way, so undo restores the stall state as exactly as it restores the sets.
            replayProgression(slots: Self.progressionSlots(of: workout))
            save()
        }
        // Re-write it to Apple Health if it had been written before (and the toggle is still on):
        // the delete above removed our own `HKWorkout`, so undo has to put that back too.
        if snapshot.healthKitID != nil, snapshot.endedAt != nil {
            onWorkoutFinished?(workout)
        }
    }
}
