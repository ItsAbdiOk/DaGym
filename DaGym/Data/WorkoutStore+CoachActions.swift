import Foundation
import GymCore
import SwiftData

/// Everything needed to put a `applyCoachDeload` back exactly as it was — the Coach screen's
/// Undo toast hands this straight back to `undoCoachDeload`. Ids, not model references, so an
/// undo tapped after a refresh still resolves against live objects.
struct CoachDeloadApplication {
    /// Each planned set that was rewritten, with the target it had before.
    fileprivate var previousTargets: [(setID: UUID, weightKg: Double?)]
    /// Each routine whose `updatedAt` was bumped, with the stamp it had before.
    fileprivate var previousRoutineStamps: [(routineID: UUID, updatedAt: Date)]
    /// What the lifter was told would happen, for the toast.
    var exerciseName: String
    var weightKg: Double
    var setCount: Int
}

/// Applying an approved `CoachSuggestedAction` back onto the store. Split out of
/// `WorkoutStore+Coach.swift`, which assembles the engine's input and never writes.
extension WorkoutStore {
    /// Applies a `.deloadExercise` suggestion: sets every working planned set's target weight for
    /// this exercise, across every non-archived routine that programmes it, and stamps those
    /// routines as edited now.
    ///
    /// **Why the stamp is the mechanism.** `ProgressionEngine` prescribes from *history* — the
    /// last logged session's first working set — and only falls back to the plan when there is no
    /// history at all. Writing a plan target on its own therefore changed nothing the lifter would
    /// ever see: the next session still prescribed the stalled weight. `AutoFill` already resolves
    /// this the right way round for the non-engine path ("a plan target edited after the previous
    /// session wins"), and `WorkoutStore+Workouts.swift`'s `prescribedEntry` now applies the same
    /// precedence to the engine's path, keyed on `RoutineModel.updatedAt`. Bumping the stamp is
    /// what makes "Approve" actually move the next session's numbers.
    ///
    /// **Why the stall state is left alone.** It used to be reset to `(misses: 0, weight: new)`.
    /// That is the one field the progression engine's own deload counts on: `resetIfWeightChanged`
    /// then saw the plan's 72 kg against history's 80 kg, read it as "the lifter changed the
    /// weight", and zeroed a miss streak that was two-thirds of the way to the engine's own
    /// deload — pushing that deload three sessions further out. Left untouched, the streak still
    /// stands, and once the lighter session is actually logged `resetIfWeightChanged` clears it
    /// for the right reason: the weight really did change.
    ///
    /// - Returns: an undo token, or nil when no routine programmes this exercise.
    @discardableResult
    func applyCoachDeload(
        exerciseID: UUID?, exerciseName: String, toWeightKg: Double, now: Date = Date()
    ) -> CoachDeloadApplication? {
        let matches = routineExercises(matching: exerciseID, name: exerciseName)
        guard !matches.isEmpty else { return nil }

        // Round onto this exercise's real grid again before writing. The engine already did
        // (`CoachRules.deloadLoad`), but the store is the last word on what is loadable and a
        // card can be approved after the lifter changes their plate inventory.
        let weightKg = roundedCoachDeload(toWeightKg, matches: matches)

        var previousTargets: [(setID: UUID, weightKg: Double?)] = []
        var previousStamps: [UUID: Date] = [:]
        for routineExercise in matches {
            for plannedSet in routineExercise.plannedSets ?? []
            where plannedSet.setKind.countsTowardStats {
                previousTargets.append((setID: plannedSet.id, weightKg: plannedSet.targetWeightKg))
                plannedSet.targetWeightKg = weightKg
            }
            if let routine = routineExercise.routine, previousStamps[routine.id] == nil {
                previousStamps[routine.id] = routine.updatedAt
                routine.updatedAt = now
            }
        }
        save()
        return CoachDeloadApplication(
            previousTargets: previousTargets,
            previousRoutineStamps: previousStamps.map { (routineID: $0.key, updatedAt: $0.value) },
            exerciseName: exerciseName, weightKg: weightKg, setCount: previousTargets.count
        )
    }

    /// Puts back exactly what `applyCoachDeload` overwrote — the planned targets and the routines'
    /// edit stamps, so the progression engine goes back to prescribing from history.
    func undoCoachDeload(_ application: CoachDeloadApplication) {
        let sets = (try? context.fetch(FetchDescriptor<PlannedSetModel>())) ?? []
        let byID = Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in application.previousTargets {
            byID[entry.setID]?.targetWeightKg = entry.weightKg
        }
        for entry in application.previousRoutineStamps {
            fetchRoutineModel(id: entry.routineID)?.updatedAt = entry.updatedAt
        }
        save()
    }

    /// Every routine-exercise slot for this exercise, in non-archived routines only.
    /// Matched by exercise **id**: matching by name hit archived routines and any other custom
    /// exercise the lifter happened to give the same name.
    private func routineExercises(matching exerciseID: UUID?, name: String) -> [RoutineExerciseModel] {
        let all = (try? context.fetch(FetchDescriptor<RoutineExerciseModel>())) ?? []
        return all.filter { routineExercise in
            guard let exercise = routineExercise.exercise,
                  routineExercise.routine?.isArchived != true else { return false }
            // The name is only a fallback for a snapshot assembled before ids were carried.
            return exerciseID.map { $0 == exercise.id } ?? (exercise.name == name)
        }
    }

    /// The heaviest real load at or below `target` on this exercise's own grid — a plate pair, a
    /// dumbbell step, a machine stack. Without it a 10 % cut off 82.5 kg was written as 74.25 kg,
    /// and an 82.5 kg lb-user's card promised an unloadable 90.7 kg.
    private func roundedCoachDeload(_ target: Double, matches: [RoutineExerciseModel]) -> Double {
        guard let exercise = matches.compactMap(\.exercise).first else { return target }
        let grid = loadGrid(for: exerciseInfo(for: exercise), equipment: activeEquipment())
        let rounded = grid.nearestBelow(target)
        return rounded > 0 ? rounded : target
    }
}
