import Foundation
import GymCore
import SwiftData

/// Everything needed to put a `applyReviewChange` back: the routines it rewrote (as the drafts
/// they had before), the schedule it moved, or the deload it applied. Handed straight back to
/// `undoReviewChange` by the Coach screen's Undo toast.
struct ReviewApplication {
    var previousRoutines: [RoutineSnapshot] = []
    var previousSchedule: WeeklySchedule?
    var deload: CoachDeloadApplication?
    /// What the lifter was told happened, for the toast.
    var message: String
}

/// A routine exactly as it was before a review change, in the shape `saveRoutine` takes.
struct RoutineSnapshot {
    var id: UUID
    var name: String
    var notes: String
    var progressionRule: String
    var repRangeLow: Int
    var repRangeHigh: Int
    var rule: ProgressionRule?
    var drafts: [RoutineExerciseDraft]
    /// The engine's stall memory per exercise id. `saveRoutine` carries it only for exercises
    /// still on the routine, so a swap loses the swapped-out lift's streak and last plan target
    /// — Undo has to write it back explicitly, or Bench comes back at 0 misses and the plan
    /// overrides the engine for one session (`planTargetWeightChanged`).
    var stallJSON: [UUID: String] = [:]
}

/// Applying an approved training-review card (plan.md §6.6: "the user approves every change,
/// and every change is undoable"). Routine edits go through `routineDrafts`/`saveRoutine` — the
/// routine builder's own round trip — so the progression engine's stall memory is carried over
/// the same way it is for a hand edit, and Undo is simply re-saving the snapshot.
extension WorkoutStore {
    /// Nil when nothing in the store matches the change (the lift is no longer programmed, the
    /// pool exercise was deleted) — the caller then records the approval without acting.
    @discardableResult
    func applyReviewChange(_ change: ReviewChange) -> ReviewApplication? {
        switch change {
        case .deloadLift(let exerciseID):
            return applyReviewDeload(exerciseID: exerciseID)
        case .addExercise(let exerciseID):
            return addReviewExercise(exerciseID: exerciseID)
        case .swapExercise(let from, let to):
            let message = "Swapped in \(exerciseName(to) ?? "exercise")"
            return editRoutines(containing: from, message: message) { drafts in
                for index in drafts.indices where drafts[index].exerciseID == from {
                    drafts[index].exerciseID = to
                }
            }
        case .changeRepRange(let exerciseID, let low, let high):
            let message = "\(exerciseName(exerciseID) ?? "Exercise") set to \(low)–\(high) reps"
            return editRoutines(containing: exerciseID, message: message) { drafts in
                Self.setRepRange(&drafts, exerciseID: exerciseID, low: low, high: high)
            }
        case .changeProgressionRule(let exerciseID, let rule):
            let message = "\(exerciseName(exerciseID) ?? "Exercise") now on \(rule.displayName)"
            return editRoutines(containing: exerciseID, message: message) { drafts in
                for index in drafts.indices where drafts[index].exerciseID == exerciseID {
                    drafts[index].overrideRule = rule
                }
            }
        case .moveRestDay(let from, let to):
            return moveTrainingDay(from: from, to: to)
        }
    }

    /// Every working set of `exerciseID` gets the new range; a single-number range clears the
    /// high end rather than storing "8–8".
    private static func setRepRange(
        _ drafts: inout [RoutineExerciseDraft], exerciseID: UUID, low: Int, high: Int
    ) {
        for index in drafts.indices where drafts[index].exerciseID == exerciseID {
            for setIndex in drafts[index].sets.indices
            where drafts[index].sets[setIndex].kind.countsTowardStats {
                drafts[index].sets[setIndex].targetReps = low
                drafts[index].sets[setIndex].targetRepsHigh = high == low ? nil : high
            }
        }
    }

    func undoReviewChange(_ application: ReviewApplication) {
        if let deload = application.deload { undoCoachDeload(deload) }
        if let schedule = application.previousSchedule { saveSchedule(schedule) }
        for snapshot in application.previousRoutines {
            resave(snapshot, drafts: snapshot.drafts)
            guard let model = fetchRoutineModel(id: snapshot.id) else { continue }
            for slot in model.exercises ?? [] {
                guard let exerciseID = slot.exercise?.id, let stall = snapshot.stallJSON[exerciseID],
                      slot.stallJSON != stall else { continue }
                slot.stallJSON = stall
            }
            save()
        }
    }

    // MARK: - Individual changes

    private func applyReviewDeload(exerciseID: UUID) -> ReviewApplication? {
        guard let exercise = fetchExerciseModel(id: exerciseID),
              let lastSet = exerciseHistory(exerciseID: exerciseID, limit: 1).first?.workingSets.first,
              case let lastWeight = lastSet.weightKg,
              lastWeight > 0 else { return nil }
        let target = lastWeight * TrainingConstants.deloadLoadFraction
        guard let applied = applyCoachDeload(
            exerciseID: exerciseID, exerciseName: exercise.name, toWeightKg: target
        ) else { return nil }
        return ReviewApplication(deload: applied, message: "\(exercise.name) deloaded")
    }

    /// Appends the exercise (3 × 8 working sets) to the routine already training its first
    /// primary muscle most, or failing that the first programmed routine.
    private func addReviewExercise(exerciseID: UUID) -> ReviewApplication? {
        guard let exercise = fetchExerciseModel(id: exerciseID) else { return nil }
        let routines = programmedRoutineModels()
        let target = routines.max { lhs, rhs in
            primarySetCount(lhs, muscles: exercise.primary) < primarySetCount(rhs, muscles: exercise.primary)
        } ?? routines.first
        guard let target, let snapshot = routineSnapshot(target) else { return nil }
        var drafts = snapshot.drafts
        drafts.append(RoutineExerciseDraft(
            exerciseID: exerciseID,
            sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8) }
        ))
        resave(snapshot, drafts: drafts)
        let msg = "Added \(exercise.name) to \(snapshot.name)"
        return ReviewApplication(previousRoutines: [snapshot], message: msg)
    }

    private func editRoutines(
        containing exerciseID: UUID, message: String, edit: (inout [RoutineExerciseDraft]) -> Void
    ) -> ReviewApplication? {
        let affected = programmedRoutineModels().filter { model in
            (model.exercises ?? []).contains { $0.exercise?.id == exerciseID }
        }
        let snapshots = affected.compactMap(routineSnapshot)
        guard !snapshots.isEmpty else { return nil }
        for snapshot in snapshots {
            var drafts = snapshot.drafts
            edit(&drafts)
            resave(snapshot, drafts: drafts)
        }
        return ReviewApplication(previousRoutines: snapshots, message: message)
    }

    private func moveTrainingDay(from: Weekday, to: Weekday) -> ReviewApplication? {
        let previous = schedule()
        guard let routines = previous.dayRoutines[from], !routines.isEmpty,
              previous.dayRoutines[to, default: []].isEmpty else { return nil }
        var updated = previous
        updated.dayRoutines[to] = routines
        updated.dayRoutines[from] = nil
        saveSchedule(updated)
        return ReviewApplication(
            previousSchedule: previous, message: "Moved \(from.displayName)'s session to \(to.displayName)"
        )
    }

    // MARK: - Helpers

    /// Non-archived routines, the active programme's first when there is one.
    private func programmedRoutineModels() -> [RoutineModel] {
        let all = fetch(FetchDescriptor<RoutineModel>(sortBy: [SortDescriptor(\.sortOrder)]))
            .filter { !$0.isArchived && $0.mergedIntoID == nil }
        guard let program = activeProgramModel(), !program.routineIDs.isEmpty else { return all }
        let programmed = Set(program.routineIDs)
        return all.filter { programmed.contains($0.id) }
    }

    private func primarySetCount(_ routine: RoutineModel, muscles: [Muscle]) -> Int {
        (routine.exercises ?? []).reduce(0) { total, slot in
            guard let exercise = slot.exercise else { return total }
            guard !Set(exercise.primary).isDisjoint(with: muscles) else { return total }
            return total + (slot.plannedSets?.count ?? 0)
        }
    }

    private func routineSnapshot(_ model: RoutineModel) -> RoutineSnapshot? {
        guard let (_, drafts) = routineDrafts(id: model.id) else { return nil }
        var stallJSON: [UUID: String] = [:]
        for slot in model.exercises ?? [] {
            if let exerciseID = slot.exercise?.id { stallJSON[exerciseID] = slot.stallJSON }
        }
        return RoutineSnapshot(
            id: model.id, name: model.name, notes: model.notes, progressionRule: model.progressionRule,
            repRangeLow: model.repRangeLow, repRangeHigh: model.repRangeHigh,
            rule: model.progressionRuleValue, drafts: drafts, stallJSON: stallJSON
        )
    }

    private func resave(_ snapshot: RoutineSnapshot, drafts: [RoutineExerciseDraft]) {
        saveRoutine(
            id: snapshot.id, name: snapshot.name, notes: snapshot.notes,
            progressionRule: snapshot.progressionRule, repRangeLow: snapshot.repRangeLow,
            repRangeHigh: snapshot.repRangeHigh, rule: snapshot.rule, exercises: drafts
        )
    }

    private func exerciseName(_ id: UUID) -> String? { fetchExerciseModel(id: id)?.name }
}
