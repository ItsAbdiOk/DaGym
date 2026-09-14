import Foundation
import GymCore
import SwiftData

/// The equipment the progression engine should round loads against.
struct ProgressionEquipment {
    var bar: Bar
    var plates: [PlateStock]
    var collarsKg: Double
}

/// The smart training engine's data plumbing (plan.md §6.5): builds `GymCore.ProgressionEngine`
/// inputs from persisted history and writes its output back. `WorkoutStore+Workouts.swift` calls
/// `computeProgression` when starting a session; `WorkoutStore+History.swift`'s `finish(session:)`
/// calls `persistProgression` once, before `endedAt` is stamped, to commit that same result —
/// see `persistProgression`'s doc comment for why the timing matters.
extension WorkoutStore {
    /// The rule that actually governs this exercise: its own override, else the routine's rule.
    /// Nil when neither is set — such a routine is *not* progressed by the engine; its sets are
    /// pre-filled by position from the last session instead (plan.md §6.1 "Smart auto-fill":
    /// the engine wins only "when one is active"). The legacy `progressionRule`/`repRange*`
    /// strings are display-only and never turn into a rule here, so routines saved before rule
    /// JSON existed keep the plain auto-fill behaviour they always had.
    func effectiveRule(routine: RoutineModel, routineExercise: RoutineExerciseModel) -> ProgressionRule? {
        routineExercise.overrideRuleValue ?? routine.progressionRuleValue
    }

    /// The engine's full output for this exercise, or nil when it's excluded from progression
    /// or has no rule (see `effectiveRule`) — the caller falls back to the plain AutoFill path.
    /// `finishedWorkouts`, when passed, is used as-is instead of re-fetching (newest first) —
    /// callers building every exercise of a routine fetch it once and share it, rather than each
    /// exercise re-querying the whole finished-workout list.
    func computeProgression(
        routine: RoutineModel, routineExercise: RoutineExerciseModel, exerciseInfo: ExerciseInfo,
        plannedSets: [PlannedSetModel], finishedWorkouts: [WorkoutModel]? = nil
    ) -> Prescribed? {
        guard !routineExercise.excludeFromProgression, let exerciseID = routineExercise.exercise?.id,
              let rule = effectiveRule(routine: routine, routineExercise: routineExercise) else {
            return nil
        }
        let specs = progressionSpecs(plannedSets)
        let equipment = activeEquipment()
        return ProgressionEngine.prescribe(
            rule: rule, planned: specs,
            history: exerciseHistory(exerciseID: exerciseID, finishedWorkouts: finishedWorkouts),
            stall: routineExercise.stallStateValue, bodyweightKg: latestBodyMeasurement()?.bodyweightKg,
            trainingMaxKg: routineExercise.trainingMaxKg, weekInCycle: weekInCycle(forRoutineID: routine.id),
            bar: exerciseInfo.bar ?? equipment.bar, plates: equipment.plates, collarsKg: equipment.collarsKg,
            grid: loadGrid(for: exerciseInfo, equipment: equipment),
            cycleIndex: cycleIndex(forRoutineID: routine.id),
            trainingMaxIncrementKg: trainingMaxIncrementKg(for: exerciseInfo)
        )
    }

    /// The equipment-appropriate rounding grid (F3/A2): plates for a bar lift, a fixed step for
    /// dumbbells/kettlebells/machines, `.free` for bodyweight/assisted/timed work where there's
    /// nothing to round.
    func loadGrid(for exerciseInfo: ExerciseInfo, equipment: ProgressionEquipment) -> LoadGrid {
        switch exerciseInfo.loggingStyle {
        case .bodyweightReps, .assisted, .timedHold, .cardio:
            return .free
        case .weightReps, .weightedBodyweight:
            break
        }
        switch exerciseInfo.equipment.lowercased() {
        case "dumbbell":
            return .step(2)
        case "kettlebell":
            return .step(4)
        case "machine", "cable":
            return .step(exerciseInfo.incrementKg > 0 ? exerciseInfo.incrementKg : 5)
        default:
            return .plates(
                bar: exerciseInfo.bar ?? equipment.bar, plates: equipment.plates,
                collarsKg: equipment.collarsKg
            )
        }
    }

    /// The active program's current cycle for `routineID` (A3) — nil when there's no active
    /// program covering it, so the TM rule never bumps outside a program.
    func cycleIndex(forRoutineID routineID: UUID) -> Int? {
        guard let program = activeProgramModel(), program.routineIDs.contains(routineID),
              let startedAt = program.startedAt, program.weeks > 0 else {
            return nil
        }
        let days = Calendar.current.dateComponents([.day], from: startedAt, to: Date()).day ?? 0
        return (max(0, days / 7) / program.weeks) + 1
    }

    /// 2.5 kg for an upper-body lift, 5 kg for a lower-body one (A3) — matches the seeded
    /// `incrementKg` split without needing a new persisted field.
    func trainingMaxIncrementKg(for exerciseInfo: ExerciseInfo) -> Double {
        return exerciseInfo.primary.contains(where: \.isLowerBody)
            ? TrainingConstants.trainingMaxLowerIncrementKg
            : TrainingConstants.trainingMaxUpperIncrementKg
    }

    /// Recomputes every non-excluded exercise's progression and persists the updated stall
    /// state / training max onto its `RoutineExerciseModel`. Called once, by
    /// `WorkoutStore+History.swift`'s `finish(session:)`, right *before* `workout.endedAt` is
    /// stamped — at that point this session is still excluded from `exerciseHistory`, so the
    /// baseline/stall inputs are identical to what `startWorkout` used to prescribe this very
    /// session; this just commits that already-shown result rather than reconsidering the
    /// session that's actually finishing (the "next" prescription's baseline only ever advances
    /// once a session is committed, matching the engine's own stall/baseline model). Called only
    /// here — never at start — so an abandoned (never-finished) workout can't burn a stall.
    func persistProgression(session: WorkoutSession) {
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID),
              let routineID = workout.routineID, let routine = fetchRoutineModel(id: routineID) else {
            return
        }
        let routineExercises = routine.exercises ?? []
        // Fetched once and shared: every exercise's `computeProgression` below would otherwise
        // re-query the whole finished-workout list from the store.
        let finishedWorkouts = finishedWorkoutModelsNewestFirst()
        for entry in session.exercises {
            guard let routineExercise = matchingRoutineExercise(entry: entry, in: routineExercises) else {
                continue
            }
            guard let plannedSets = routineExercise.plannedSets, let result = computeProgression(
                routine: routine, routineExercise: routineExercise, exerciseInfo: entry.exercise,
                plannedSets: plannedSets, finishedWorkouts: finishedWorkouts
            ) else {
                continue
            }
            routineExercise.stallStateValue = result.stall
            routineExercise.trainingMaxKg = result.trainingMaxKg
        }
    }

    /// Up to the last 6 finished workouts' sets for this exercise, newest first, as
    /// `GymCore.ExerciseHistoryEntry` — the shape `ProgressionEngine.prescribe` expects. A
    /// session logged under an excluded routine slot (`excludedFromProgression`) is not history
    /// the engine may build on, so it's left out here rather than flagged. Pass `finishedWorkouts`
    /// (newest first) to reuse an already-fetched list instead of querying the store again.
    func exerciseHistory(
        exerciseID: UUID, limit: Int = 6, finishedWorkouts: [WorkoutModel]? = nil
    ) -> [ExerciseHistoryEntry] {
        var result: [ExerciseHistoryEntry] = []
        for workout in finishedWorkouts ?? finishedWorkoutModelsNewestFirst() {
            guard let match = matchingExercise(exerciseID: exerciseID, in: workout),
                  !match.excludedFromProgression else { continue }
            let sets = completedHistorySets(match)
            guard !sets.isEmpty else { continue }
            result.append(
                ExerciseHistoryEntry(
                    date: workout.startedAt, sets: sets, wasPlannedDeload: match.wasPlannedDeload
                )
            )
            if result.count == limit { break }
        }
        return result
    }

    /// The equipment the engine should round against — the active profile's bar/plates/collars,
    /// falling back to the Olympic bar and a standard kg set when no profile exists yet.
    func activeEquipment() -> ProgressionEquipment {
        guard let profile = activeProfile() else {
            return ProgressionEquipment(bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
        }
        return ProgressionEquipment(
            bar: Bar(name: profile.name, weightKg: profile.barKg), plates: profile.plateStock,
            collarsKg: profile.collarsKg
        )
    }

    func finishedWorkoutModelsNewestFirst() -> [WorkoutModel] {
        finishedWorkoutsQueryCount += 1
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Helpers

    private func progressionSpecs(_ plannedSets: [PlannedSetModel]) -> [PlannedSetSpec] {
        plannedSets.sorted { $0.order < $1.order }.map { model in
            PlannedSetSpec(
                kind: model.setKind, targetReps: model.targetReps, targetSeconds: model.targetSeconds,
                targetRPE: model.targetRPE
            )
        }
    }

    private func matchingRoutineExercise(
        entry: WorkoutExerciseEntry, in routineExercises: [RoutineExerciseModel]
    ) -> RoutineExerciseModel? {
        routineExercises.first { $0.exercise?.id == entry.exercise.id && !$0.excludeFromProgression }
    }

    private func matchingExercise(exerciseID: UUID, in workout: WorkoutModel) -> WorkoutExerciseModel? {
        (workout.exercises ?? []).first { $0.exercise?.id == exerciseID }
    }

    private func completedHistorySets(_ model: WorkoutExerciseModel) -> [HistorySet] {
        (model.sets ?? []).filter(\.isCompleted).sorted { $0.order < $1.order }.map(Self.historySet)
    }

    private static func historySet(from model: SetLogModel) -> HistorySet {
        HistorySet(
            kind: model.setKind, weightKg: model.weightKg, reps: model.reps,
            effort: model.rpe.map { Effort(rpe: $0) }, durationSeconds: model.durationSeconds,
            assistanceKg: model.assistanceKg
        )
    }
}
