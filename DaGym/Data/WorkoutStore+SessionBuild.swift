import Foundation
import GymCore
import SwiftData

/// Building the entries of a session from a routine's planned sets: the engine's prescription,
/// the plan-outranks-engine rule, planned deloads and the plain previous-session auto-fill.
/// `startWorkout`/`appendRoutine`/`startBackfill` and `sync` live in `WorkoutStore+Workouts.swift`.
extension WorkoutStore {
    // One planned set as (kind, target reps, target weight, target seconds) — the shape
    // `GymCore.AutoFill.prescriptions` expects. Named distinctly from `GymCore.PlannedSetSpec`
    // (the progression engine's own type), which this file also uses.
    // swiftlint:disable:next large_tuple
    typealias AutoFillSetSpec = (
        kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?
    )

    func buildEntries(
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
        if info.loggingStyle == .cardio {
            return cardioEntry(
                info: info, plannedSets: plannedSets, routineExercise: routineExercise, facts: facts
            )
        }
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
    func autoFilledSets(
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
}
