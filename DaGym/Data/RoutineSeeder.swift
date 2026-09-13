import Foundation
import GymCore

/// Seeds three starter routines ("Push A", "Pull B", "Legs") the first time
/// the app has none. Exercises are looked up by name against the already
/// seeded exercise library, falling back to the first exercise with the
/// right primary muscle when a specific name isn't present.
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

        let exercises = [
            RoutineExerciseDraft(
                exerciseID: bench.id,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 10, targetWeightKg: 40),
                    PlannedSetDraft(kind: .warmup, targetReps: 5, targetWeightKg: 60)
                ] + (0..<3).map { _ in
                    PlannedSetDraft(kind: .working, targetReps: 6, targetRepsHigh: 8, targetRPE: 8)
                }
            ),
            RoutineExerciseDraft(
                exerciseID: incline.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 10) }
            ),
            RoutineExerciseDraft(
                exerciseID: shoulderPress.id,
                sets: (0..<4).map { _ in PlannedSetDraft(kind: .working, targetReps: 6) }
            ),
            RoutineExerciseDraft(
                exerciseID: crossover.id, supersetGroup: 1,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 12) }
            ),
            RoutineExerciseDraft(exerciseID: pushdown.id, supersetGroup: 1, sets: pushdownSets)
        ]
        store.saveRoutine(
            id: nil, name: "Push A", progressionRule: "doubleProgression", repRangeLow: 6, repRangeHigh: 8,
            exercises: exercises
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

        let exercises = [
            RoutineExerciseDraft(
                exerciseID: deadlift.id,
                sets: [PlannedSetDraft(kind: .warmup, targetReps: 8, targetWeightKg: 60)]
                    + (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 5) }
            ),
            RoutineExerciseDraft(
                exerciseID: pullups.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8) }
            ),
            RoutineExerciseDraft(
                exerciseID: row.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8) }
            ),
            RoutineExerciseDraft(
                exerciseID: curl.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 12) }
            )
        ]
        store.saveRoutine(id: nil, name: "Pull B", progressionRule: "linear", exercises: exercises)
    }

    // MARK: - Legs

    private static func seedLegs(store: WorkoutStore) {
        guard
            let squat = lookup(store, "Barbell Squat", fallback: "Squat", muscle: .quads),
            let legCurl = lookup(store, "Lying Leg Curls", fallback: "Leg Curl", muscle: .hams),
            let calfRaise = lookup(store, "Standing Calf Raises", fallback: "Calf Raise", muscle: .calves),
            let plank = lookup(store, "Plank", muscle: .abs)
        else { return }

        let exercises = [
            RoutineExerciseDraft(
                exerciseID: squat.id,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 8, targetWeightKg: 40),
                    PlannedSetDraft(kind: .warmup, targetReps: 5, targetWeightKg: 60)
                ] + (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 5) }
            ),
            RoutineExerciseDraft(
                exerciseID: legCurl.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 10) }
            ),
            RoutineExerciseDraft(
                exerciseID: calfRaise.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 15) }
            ),
            RoutineExerciseDraft(
                exerciseID: plank.id,
                sets: (0..<3).map { _ in PlannedSetDraft(kind: .working, targetSeconds: 60) }
            )
        ]
        store.saveRoutine(id: nil, name: "Legs", progressionRule: "linear", exercises: exercises)
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
