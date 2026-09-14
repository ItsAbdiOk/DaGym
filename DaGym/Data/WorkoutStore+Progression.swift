import Foundation
import GymCore
import SwiftData

/// The equipment the progression engine should round loads against.
struct ProgressionEquipment {
    var bar: Bar
    var plates: [PlateStock]
    var collarsKg: Double
}

/// The facts that are the same for *every* exercise in one session build — the equipment
/// profile in force, today's bodyweight, where the active program stands, the finished-workout
/// list, and the cached PR/session-count rows. Each is a property of the session, not of an
/// exercise, so re-deriving it per exercise cost a store round trip and returned the identical
/// answer every time (plan.md §6.5's N+1). `startWorkout`, `appendRoutine`, `resumeSession`,
/// `autoFilledEntry` and `persistProgression` build one of these up front and thread it through;
/// `nil` at a call site means "look it up yourself", which is what every single-exercise caller
/// outside those paths still does.
struct SessionFacts {
    var finishedWorkouts: [WorkoutModel] = []
    var equipment = ProgressionEquipment(bar: .olympic, plates: PlateStock.standardKg, collarsKg: 0)
    var bodyweightKg: Double?
    var weekInCycle: Int?
    var cycleIndex: Int?
    var weekKind: ProgramWeekKind?
    /// Best cached e1RM row per exercise, and how many finished workout-exercise rows each has —
    /// the two stats `exerciseInfo(for:)` would otherwise query once per exercise.
    var bestE1RM: [UUID: PersonalRecordModel] = [:]
    var sessionCounts: [UUID: Int] = [:]
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

    /// Every per-session fact one routine build needs, in a fixed number of queries regardless
    /// of how many exercises the routine has. `routineID` is nil for a build with no routine
    /// behind it (a freshly added exercise), where the program lookups have no answer anyway
    /// and so aren't paid for.
    func makeSessionFacts(routineID: UUID?) -> SessionFacts {
        let finished = finishedWorkoutModelsNewestFirst()
        var facts = SessionFacts(
            finishedWorkouts: finished,
            equipment: activeEquipment(),
            bodyweightKg: latestBodyMeasurement()?.bodyweightKg,
            bestE1RM: bestE1RMRecordsByExercise(),
            sessionCounts: Self.sessionCounts(in: finished)
        )
        guard let routineID else { return facts }
        let program = activeProgramModel()
        facts.weekInCycle = weekInCycle(forRoutineID: routineID, activeProgram: program)
        facts.cycleIndex = cycleIndex(forRoutineID: routineID, activeProgram: program)
        facts.weekKind = currentWeekKind(forRoutineID: routineID, activeProgram: program)
        return facts
    }

    /// Finished workout-exercise rows per exercise — the same number
    /// `WorkoutStore+Exercises.swift`'s `sessionCount(exerciseID:)` counts with a `fetchCount`,
    /// read off the finished-workout list we already hold instead.
    private static func sessionCounts(in finished: [WorkoutModel]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for workout in finished {
            for exercise in workout.exercises ?? [] {
                guard let id = exercise.exercise?.id else { continue }
                counts[id, default: 0] += 1
            }
        }
        return counts
    }

    /// The engine's full output for this exercise, or nil when it's excluded from progression
    /// or has no rule (see `effectiveRule`) — the caller falls back to the plain AutoFill path.
    /// `facts`, when passed, supplies the finished-workout list, equipment, bodyweight and
    /// program position as-is instead of re-querying each of them: a caller building every
    /// exercise of a routine fetches them once and shares them (see `SessionFacts`).
    func computeProgression(
        routine: RoutineModel, routineExercise: RoutineExerciseModel, exerciseInfo: ExerciseInfo,
        plannedSets: [PlannedSetModel], facts: SessionFacts? = nil
    ) -> Prescribed? {
        guard !routineExercise.excludeFromProgression, let exerciseID = routineExercise.exercise?.id,
              let rule = effectiveRule(routine: routine, routineExercise: routineExercise) else {
            return nil
        }
        let shared = facts ?? makeSessionFacts(routineID: routine.id)
        let equipment = shared.equipment
        return ProgressionEngine.prescribe(
            rule: rule, planned: progressionSpecs(plannedSets),
            history: exerciseHistory(exerciseID: exerciseID, finishedWorkouts: shared.finishedWorkouts),
            stall: routineExercise.stallStateValue, bodyweightKg: shared.bodyweightKg,
            trainingMaxKg: routineExercise.trainingMaxKg, weekInCycle: shared.weekInCycle,
            bar: exerciseInfo.bar ?? equipment.bar, plates: equipment.plates, collarsKg: equipment.collarsKg,
            grid: loadGrid(for: exerciseInfo, equipment: equipment),
            cycleIndex: shared.cycleIndex,
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
        cycleIndex(forRoutineID: routineID, activeProgram: activeProgramModel())
    }

    /// `cycleIndex(forRoutineID:)` against an already-fetched active program — see
    /// `weekInCycle(forRoutineID:activeProgram:)`.
    func cycleIndex(forRoutineID routineID: UUID, activeProgram: ProgramModel?) -> Int? {
        guard let program = activeProgram, program.routineIDs.contains(routineID),
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
        // re-query the finished-workout list, the equipment profile, the latest bodyweight and
        // the active program — none of which can differ between the exercises of one session.
        let facts = makeSessionFacts(routineID: routineID)
        for entry in session.exercises {
            guard let routineExercise = matchingRoutineExercise(entry: entry, in: routineExercises) else {
                continue
            }
            guard let plannedSets = routineExercise.plannedSets, let result = computeProgression(
                routine: routine, routineExercise: routineExercise, exerciseInfo: entry.exercise,
                plannedSets: plannedSets, facts: facts
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
        let predicate = #Predicate<WorkoutModel> { $0.endedAt != nil }
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return fetch(descriptor)
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
