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
    ///
    /// `calendar` decides which calendar the program's weeks are measured in — the lifter's own
    /// `Preferences.trainingCalendar`, passed down from the call site the way `unit:` is, because
    /// the store never reads `Preferences` itself. Left at `.current` it fell back to the device
    /// locale's week start, so a Sunday-start lifter could be handed a planned deload on a
    /// different day from the one the Programmes screen showed them.
    func makeSessionFacts(routineID: UUID?, calendar: Calendar = .current) -> SessionFacts {
        let finished = finishedWorkoutModelsNewestFirst()
        var facts = SessionFacts(
            finishedWorkouts: finished,
            equipment: activeEquipment(),
            bodyweightKg: latestBodyMeasurement()?.bodyweightKg,
            bestE1RM: bestE1RMRecordsByExercise(),
            sessionCounts: Self.sessionCounts(in: finished)
        )
        guard let routineID else { return facts }
        let now = Date()
        let program = activeProgramModel(now: now, calendar: calendar)
        facts.weekInCycle = weekInCycle(
            forRoutineID: routineID, activeProgram: program, now: now, calendar: calendar
        )
        facts.cycleIndex = cycleIndex(
            forRoutineID: routineID, activeProgram: program, now: now, calendar: calendar
        )
        facts.weekKind = currentWeekKind(
            forRoutineID: routineID, activeProgram: program, now: now, calendar: calendar
        )
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
            trainingMaxIncrementKg: trainingMaxIncrementKg(for: exerciseInfo),
            // Unilateral work logs both sides as one total, so rep targets step by 2 and stay
            // even. GymCore has always taken this; the store never passed it, so every per-side
            // exercise in the app stepped by 1 and odd rep ranges were never evened.
            perSide: exerciseInfo.isPerSide
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
    func cycleIndex(
        forRoutineID routineID: UUID, activeProgram: ProgramModel?, now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        guard let program = activeProgram, program.routineIDs.contains(routineID),
              let startedAt = program.startedAt, program.weeks > 0 else {
            return nil
        }
        // Whole calendar weeks, and nil once the program has run its repetitions out — see
        // `GymCore.ProgramCycle`. The old `days / 7` climbed forever, so the training-max rule
        // kept bumping every `weeks` weeks for as long as the program stayed active.
        return ProgramCycle.position(
            startedAt: startedAt, now: now, weeks: program.weeks, calendar: calendar
        )?.cycle
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
    ///
    /// Only exercises whose row *will* become the next baseline are committed. A planned-deload
    /// row and a row with nothing completed are both skipped by `exerciseHistory`, so they never
    /// become a baseline — committing them re-judged the baseline the previous session had
    /// already been judged against, and the next start judged it a third time. A lifter on
    /// linear who missed twice and then took a planned deload week reached the engine's
    /// three-miss deload with only two real misses behind it.
    ///
    /// A multi-routine day (`appendRoutine`) is committed per entry, against the routine the
    /// entry actually came from, not against `WorkoutModel.routineID` — which names only the
    /// first routine, so every lift appended from a second one used to accumulate no misses at
    /// all and could never deload.
    func persistProgression(session: WorkoutSession) {
        guard let workoutID = session.workoutID, let workout = fetchWorkoutModel(id: workoutID) else {
            return
        }
        // `SessionFacts` is per routine (the program week/cycle is), and cached: the common
        // single-routine session still pays for exactly one build, as it did before.
        var factsByRoutine: [UUID: SessionFacts] = [:]
        for entry in session.exercises where Self.becomesNextBaseline(entry) {
            guard let routineID = entry.routineID ?? workout.routineID,
                  let routine = fetchRoutineModel(id: routineID) else { continue }
            let facts: SessionFacts
            if let cached = factsByRoutine[routineID] {
                facts = cached
            } else {
                facts = makeSessionFacts(routineID: routineID)
                factsByRoutine[routineID] = facts
            }
            persistProgression(entry: entry, routine: routine, facts: facts)
            // `RoutineModel.updatedAt` is what `RoutineSeeder`'s CloudKit fold picks a survivor
            // by. Committing a judgement without touching it left the device that had actually
            // been *training* looking older than one where the routine had merely been renamed,
            // and the fold discarded weeks of stall state and training maxes in favour of the
            // rename.
            //
            // Stamped with the session's own start, not `Date()`, and never moved backwards.
            // `updatedAt` has a second job — `AutoFill` and `planOverridesPrescription` ask "is
            // the plan newer than the session the numbers came from?" — and "now" is always
            // newer than the session finishing right now, so a plain bump would have made the
            // plan outrank the engine after every single workout, taking the previous-session
            // ghost off every row with it. The session's own date ties, and a tie is not newer.
            routine.updatedAt = max(routine.updatedAt, workout.startedAt)
        }
    }

    /// Commits one finished entry's judgement onto its routine slot. Nothing is written when the
    /// slot is excluded from progression or has no rule — `computeProgression` returns nil and
    /// the lift keeps whatever state it had.
    private func persistProgression(entry: WorkoutExerciseEntry, routine: RoutineModel, facts: SessionFacts) {
        guard let routineExercise = matchingRoutineExercise(entry: entry, in: routine.exercises ?? []),
              let plannedSets = routineExercise.plannedSets,
              let result = computeProgression(
                  routine: routine, routineExercise: routineExercise, exerciseInfo: entry.exercise,
                  plannedSets: plannedSets, facts: facts
              ) else { return }
        routineExercise.stallStateValue = result.stall
        routineExercise.trainingMaxKg = result.trainingMaxKg
    }

    /// Whether this finished row becomes the baseline the *next* session's prescription is
    /// judged against — the exact test `exerciseHistory` applies when it builds the engine's
    /// history, mirrored here so a row that will never be a baseline is never judged from.
    /// `excludedFromProgression` needs no test: `matchingRoutineExercise` already skips those
    /// slots, and `exerciseHistory` already skips their rows.
    static func becomesNextBaseline(_ entry: WorkoutExerciseEntry) -> Bool {
        !entry.wasPlannedDeload && entry.sets.contains(where: \.isDone)
    }

    /// Whether this exercise's plan names a working target weight that is *different* from the
    /// one recorded the last time the engine judged it (`StallState.lastPlanTargetWeightKg`).
    ///
    /// This is the whole of `WorkoutStore.planOverridesPrescription`'s decision beyond the
    /// `RoutineModel.updatedAt` gate, and it lives here because the stamp alone cannot answer it:
    /// `saveRoutine` bumps `updatedAt` on every save — a rename, a reorder, a glyph — while "some
    /// working set has a target weight" is permanently true once it is true at all. Comparing the
    /// number instead makes a plan override (a hand edit, or an approved Coach deload) last
    /// exactly one session: finishing that session records the new target, and the two match.
    /// No recorded target at all means the engine has never judged this lift, so the plan wins.
    static func planTargetWeightChanged(_ plannedSets: [PlannedSetModel]) -> Bool {
        let working = plannedSets.first { $0.setKind.countsTowardStats && $0.targetWeightKg != nil }
        guard let target = working?.targetWeightKg else { return false }
        let seen = working?.routineExercise?.stallStateValue.lastPlanTargetWeightKg
        return seen.map { !StallState.sameWeight($0, target) } ?? true
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

    /// The equipment the engine should round against. One line so there is exactly one answer
    /// in the app: see `WorkoutStore.activeInventory()`, which every weight-loading surface
    /// (plate chip, keypad plate line, 1RM percent table) now reads too.
    func activeEquipment() -> ProgressionEquipment { activeInventory() }

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
                targetRPE: model.targetRPE, targetWeightKg: model.targetWeightKg
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
