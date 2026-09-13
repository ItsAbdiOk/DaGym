import Foundation
import GymCore

/// Seeds three starter routines ("Push A", "Pull B", "Legs") the first time
/// the app has none. Exercises are looked up by name against the already
/// seeded exercise library, falling back to the first exercise with the
/// right primary muscle when a specific name isn't present.
///
/// Every starter routine carries an explicit progression rule (plan.md §6.5) so the engine
/// prescribes from the first session on — a routine saved without a rule is pre-filled by
/// position from the last session instead (`WorkoutStore.effectiveRule`). Exercises whose
/// increment or logging style doesn't fit the routine's rule get a per-exercise override
/// (`starterOverride`): lower-body lifts step 5 kg, bodyweight work goes by reps, holds by seconds.
@MainActor
enum RoutineSeeder {
    static func seedStarterRoutinesIfNeeded(store: WorkoutStore) {
        guard store.routines().isEmpty else { return }
        seedPushA(store: store)
        seedPullB(store: store)
        seedLegs(store: store)
    }

    // MARK: - Push A

    private static func seedPushA(store: WorkoutStore) {
        guard
            let bench = lookup(
                store, "Barbell Bench Press - Medium Grip", fallback: "Bench Press", muscle: .chest
            ),
            let incline = lookup(store, "Incline Dumbbell Press", muscle: .chest),
            let shoulderPress = lookup(store, "Barbell Shoulder Press", muscle: .delts),
            let crossover = lookup(store, "Cable Crossover", muscle: .chest),
            let pushdown = lookup(store, "Triceps Pushdown", muscle: .triceps)
        else { return }

        var pushdownSets = (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 12) }
        pushdownSets[pushdownSets.count - 1].kind = .drop

        let rule = ProgressionRule.doubleProgression(
            low: 6, high: 8, incrementKg: TrainingConstants.defaultUpperBodyIncrementKg
        )
        let exercises = [
            RoutineExerciseDraft(
                exerciseID: bench.id,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                    PlannedSetDraft(kind: .warmup, targetReps: 5, targetWeightKg: 60)
                ] + (0..<3).map { _ in
                    PlannedSetDraft(kind: .working, targetReps: 6, targetRepsHigh: 8, targetRPE: 8)
                },
                overrideRule: starterOverride(for: bench, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: incline.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 10) },
                overrideRule: starterOverride(for: incline, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: shoulderPress.id,
                sets: (0..<4).map { _ in PlannedSetDraft(kind: .working, targetReps: 6) },
                overrideRule: starterOverride(for: shoulderPress, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: crossover.id, supersetGroup: 1,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 12) },
                overrideRule: starterOverride(for: crossover, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: pushdown.id, supersetGroup: 1, sets: pushdownSets,
                overrideRule: starterOverride(for: pushdown, routineRule: rule)
            )
        ]
        store.saveRoutine(
            id: nil, name: "Push A", progressionRule: "doubleProgression", repRangeLow: 6, repRangeHigh: 8,
            rule: rule, exercises: exercises
        )
    }

    // MARK: - Pull B

    private static func seedPullB(store: WorkoutStore) {
        guard
            let deadlift = lookup(store, "Barbell Deadlift", fallback: "Deadlift", muscle: .hams),
            let pullups = lookup(store, "Pullups", fallback: "Pull-Up", muscle: .lats),
            let row = lookup(store, "Bent Over Barbell Row", muscle: .lats),
            let curl = lookup(store, "Dumbbell Bicep Curl", muscle: .biceps)
        else { return }

        let rule = ProgressionRule.linear(incrementKg: TrainingConstants.defaultUpperBodyIncrementKg)
        let exercises = [
            RoutineExerciseDraft(
                exerciseID: deadlift.id,
                sets: [PlannedSetDraft(kind: .warmup, targetReps: 8, targetWeightKg: 60)]
                    + (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 5) },
                overrideRule: starterOverride(for: deadlift, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: pullups.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8) },
                overrideRule: starterOverride(for: pullups, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: row.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8) },
                overrideRule: starterOverride(for: row, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: curl.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 12) },
                overrideRule: starterOverride(for: curl, routineRule: rule)
            )
        ]
        store.saveRoutine(
            id: nil, name: "Pull B", progressionRule: "linear", rule: rule, exercises: exercises
        )
    }

    // MARK: - Legs

    private static func seedLegs(store: WorkoutStore) {
        guard
            let squat = lookup(store, "Barbell Squat", fallback: "Squat", muscle: .quads),
            let legCurl = lookup(store, "Lying Leg Curls", fallback: "Leg Curl", muscle: .hams),
            let calfRaise = lookup(store, "Standing Calf Raises", fallback: "Calf Raise", muscle: .calves),
            let plank = lookup(store, "Plank", muscle: .abs)
        else { return }

        let rule = ProgressionRule.linear(incrementKg: TrainingConstants.defaultUpperBodyIncrementKg)
        let exercises = [
            RoutineExerciseDraft(
                exerciseID: squat.id,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 8, targetWeightKg: 40),
                    PlannedSetDraft(kind: .warmup, targetReps: 5, targetWeightKg: 60)
                ] + (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 5) },
                overrideRule: starterOverride(for: squat, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: legCurl.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 10) },
                overrideRule: starterOverride(for: legCurl, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: calfRaise.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 15) },
                overrideRule: starterOverride(for: calfRaise, routineRule: rule)
            ),
            RoutineExerciseDraft(
                exerciseID: plank.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetSeconds: 60) },
                overrideRule: starterOverride(for: plank, routineRule: rule)
            )
        ]
        store.saveRoutine(id: nil, name: "Legs", progressionRule: "linear", rule: rule, exercises: exercises)
    }

    // MARK: - Overrides

    /// The per-exercise rule a starter routine's weight-based rule can't express: bodyweight
    /// reps, timed holds, assisted work, and any lift whose seeded increment isn't the routine's
    /// (lower-body lifts step 5 kg, dumbbells 2 kg) — those keep the routine's rule shape with
    /// the exercise's own increment. Nil when the routine's rule already fits.
    static func starterOverride(
        for exercise: ExerciseInfo, routineRule: ProgressionRule
    ) -> ProgressionRule? {
        switch exercise.loggingStyle {
        case .bodyweightReps, .weightedBodyweight:
            // plan.md §6.1: bodyweight work progresses by reps, then sets — added load is manual.
            return .bodyweight(
                repCeiling: TrainingConstants.bodyweightRepCeiling,
                maxSets: TrainingConstants.bodyweightMaxSets
            )
        case .timedHold:
            return .timed(stepSeconds: TrainingConstants.defaultTimedStepSeconds)
        case .assisted:
            return .assisted(stepKg: TrainingConstants.defaultAssistedStepKg)
        case .cardio:
            return nil
        case .weightReps:
            guard exercise.incrementKg > 0 else { return nil }
            switch routineRule {
            case .linear(let incrementKg) where incrementKg != exercise.incrementKg:
                return .linear(incrementKg: exercise.incrementKg)
            case .doubleProgression(let low, let high, let incrementKg)
                where incrementKg != exercise.incrementKg:
                return .doubleProgression(low: low, high: high, incrementKg: exercise.incrementKg)
            default:
                return nil
            }
        }
    }

    // MARK: - Lookup

    /// Finds an exercise by exact name, falling back to the first search
    /// result for `fallback` (or `name` if no separate fallback is given),
    /// then to the first exercise whose primary muscle matches.
    private static func lookup(
        _ store: WorkoutStore, _ name: String, fallback: String? = nil, muscle: Muscle
    ) -> ExerciseInfo? {
        let candidates = store.exercises(matching: name)
        if let exact = candidates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact
        }
        if let first = candidates.first { return first }
        if let fallback, fallback != name {
            let fallbackCandidates = store.exercises(matching: fallback)
            if let first = fallbackCandidates.first { return first }
        }
        return store.exercises(muscle: muscle).first { $0.primary.contains(muscle) }
    }
}
