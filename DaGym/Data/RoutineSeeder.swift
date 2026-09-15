import Foundation
import GymCore
import SwiftData

/// Seeds the starter routines once per store (`SeedStateModel.routinesSeeded`): the
/// Push/Pull/Legs trio ("Push A", "Pull B", "Legs") plus the routines each starter program
/// cycles — Upper/Lower A/B, Full Body A/B/C and 5×5 A/B/C (`StarterProgramKind.routineNames`).
/// A store seeded before the program routines existed gets them on the next launch, as long
/// as none of them is present yet. Exercises are looked up by name against
/// the already seeded exercise library, falling back to the first exercise
/// with the right primary muscle when a specific name isn't present. Each
/// starter carries a fixed `importedFromID` so a copy seeded by another iCloud
/// device folds into this one (`WorkoutStore.dedupeRoutines()`).
///
/// Every starter routine carries an explicit progression rule (plan.md §6.5) so the engine
/// prescribes from the first session on — a routine saved without a rule is pre-filled by
/// position from the last session instead (`WorkoutStore.effectiveRule`). Exercises whose
/// increment or logging style doesn't fit the routine's rule get a per-exercise override
/// (`starterOverride`): lower-body lifts step 5 kg, bodyweight work goes by reps, holds by seconds.
@MainActor
enum RoutineSeeder {
    /// Stable per-starter identities, shared by every install.
    static let starterIDs: [String: UUID] = [
        "Push A": starterID(1), "Pull B": starterID(2), "Legs": starterID(3),
        "Upper A": starterID(4), "Lower A": starterID(5), "Upper B": starterID(6), "Lower B": starterID(7),
        "Full Body A": starterID(8), "Full Body B": starterID(9), "Full Body C": starterID(10),
        "5×5 A": starterID(11), "5×5 B": starterID(12), "5×5 C": starterID(13)
    ]

    /// The routines behind every non-PPL starter program, in seeding order.
    static let programRoutineNames = [
        "Upper A", "Lower A", "Upper B", "Lower B",
        "Full Body A", "Full Body B", "Full Body C",
        "5×5 A", "5×5 B", "5×5 C"
    ]

    private static func starterID(_ index: Int) -> UUID {
        let group = String(format: "%04X", index)
        let node = String(format: "%012X", index)
        return UUID(uuidString: "6D1A5D4E-\(group)-4A00-8000-\(node)") ?? UUID()
    }

    /// Folding two devices' copies of a starter (`WorkoutStore.dedupeRoutines()`) is left to
    /// `dedupeSeededRows()`, which every launch runs once after all three seeders — a `defer`
    /// here used to run the same full routine fetch a second time on every cold start.
    static func seedStarterRoutinesIfNeeded(store: WorkoutStore) {
        let state = SeedState.row(in: store.context)
        if !state.routinesSeeded {
            if store.routines().isEmpty {
                let catalogue = store.exerciseCatalogue()
                seedPushA(store: store, catalogue: catalogue)
                seedPullB(store: store, catalogue: catalogue)
                seedLegs(store: store, catalogue: catalogue)
                seedProgramRoutines(store: store, catalogue: catalogue)
            }
            state.routinesSeeded = true
            state.updatedAt = Date()
            store.save()
            return
        }
        seedProgramRoutinesIfMissing(store: store)
    }

    /// Adds the program routines to a store that was seeded before they existed. Only fires when
    /// the store still has routines but none of these, so deleting one (or all) stays deleted.
    private static func seedProgramRoutinesIfMissing(store: WorkoutStore) {
        let programIDs = Set(programRoutineNames.compactMap { starterIDs[$0] })
        let models = store.fetch(FetchDescriptor<RoutineModel>()).filter { !$0.isMergedAway }
        guard !models.isEmpty else { return }
        let existingNames = Set(models.map(\.name))
        let alreadyThere = models.contains { $0.importedFromID.map(programIDs.contains) ?? false }
            || programRoutineNames.contains(where: existingNames.contains)
        guard !alreadyThere else { return }
        seedProgramRoutines(store: store)
        store.save()
    }

    /// `catalogue` is the library read once for the whole seed; every slot lookup runs against it.
    static func seedProgramRoutines(
        store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue? = nil
    ) {
        let catalogue = catalogue ?? store.exerciseCatalogue()
        for spec in programRoutineSpecs() {
            seed(spec, store: store, catalogue: catalogue)
        }
    }

    static func stamp(_ routine: RoutineInfo, store: WorkoutStore) {
        guard let model = store.fetchRoutineModel(id: routine.id) else { return }
        model.importedFromID = starterIDs[routine.name]
    }

    // MARK: - Push A

    private static func seedPushA(store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue) {
        guard
            let bench = lookup(
                catalogue, "Barbell Bench Press - Medium Grip", fallback: "Bench Press", muscle: .chest
            ),
            let incline = lookup(catalogue, "Incline Dumbbell Press", muscle: .chest),
            let shoulderPress = lookup(catalogue, "Barbell Shoulder Press", muscle: .delts),
            let crossover = lookup(catalogue, "Cable Crossover", muscle: .chest),
            let pushdown = lookup(catalogue, "Triceps Pushdown", muscle: .triceps)
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
                    PlannedSetDraft(kind: .warmup, targetReps: 10),
                    PlannedSetDraft(kind: .warmup, targetReps: 5)
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
        let routine = store.saveRoutine(
            id: nil, name: "Push A", progressionRule: "doubleProgression", repRangeLow: 6, repRangeHigh: 8,
            rule: rule, exercises: exercises
        )
        stamp(routine, store: store)
    }

    // MARK: - Pull B

    private static func seedPullB(store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue) {
        guard
            let deadlift = lookup(catalogue, "Barbell Deadlift", fallback: "Deadlift", muscle: .hams),
            let pullups = lookup(catalogue, "Pullups", fallback: "Pull-Up", muscle: .lats),
            let row = lookup(catalogue, "Bent Over Barbell Row", muscle: .lats),
            let curl = lookup(catalogue, "Dumbbell Bicep Curl", muscle: .biceps)
        else { return }

        let rule = ProgressionRule.linear(incrementKg: TrainingConstants.defaultUpperBodyIncrementKg)
        let exercises = [
            RoutineExerciseDraft(
                exerciseID: deadlift.id,
                sets: [PlannedSetDraft(kind: .warmup, targetReps: 8)]
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
        let routine = store.saveRoutine(
            id: nil, name: "Pull B", progressionRule: "linear", rule: rule, exercises: exercises
        )
        stamp(routine, store: store)
    }

    // MARK: - Legs

    private static func seedLegs(store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue) {
        guard
            let squat = lookup(catalogue, "Barbell Squat", fallback: "Squat", muscle: .quads),
            let legCurl = lookup(catalogue, "Lying Leg Curls", fallback: "Leg Curl", muscle: .hams),
            let calfRaise = lookup(
                catalogue, "Standing Calf Raises", fallback: "Calf Raise", muscle: .calves
            ),
            let plank = lookup(catalogue, "Plank", muscle: .abs)
        else { return }

        let rule = ProgressionRule.linear(incrementKg: TrainingConstants.defaultUpperBodyIncrementKg)
        let exercises = [
            RoutineExerciseDraft(
                exerciseID: squat.id,
                sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 8),
                    PlannedSetDraft(kind: .warmup, targetReps: 5)
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
        let routine = store.saveRoutine(
            id: nil, name: "Legs", progressionRule: "linear", rule: rule, exercises: exercises
        )
        stamp(routine, store: store)
    }

    // MARK: - Overrides

    /// The per-exercise rule a starter routine's weight-based rule can't express: bodyweight
    /// reps, timed holds, assisted work, and any lift whose seeded increment isn't the routine's
    /// (lower-body lifts step `TrainingConstants.defaultLowerBodyIncrementKg`, dumbbells 2 kg) —
    /// those keep the routine's rule shape with the exercise's own increment. Nil when the
    /// routine's rule already fits.
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
            let increment = starterIncrementKg(for: exercise)
            guard increment > 0 else { return nil }
            switch routineRule {
            case .linear(let incrementKg) where incrementKg != increment:
                return .linear(incrementKg: increment)
            case .doubleProgression(let low, let high, let incrementKg) where incrementKg != increment:
                return .doubleProgression(low: low, high: high, incrementKg: increment)
            default:
                return nil
            }
        }
    }

    /// A lower-body lift seeds with the lower-body default step (5 kg), whatever its library
    /// increment says; everything else keeps the library's own increment (dumbbells 2 kg…).
    static func starterIncrementKg(for exercise: ExerciseInfo) -> Double {
        exercise.primary.contains(where: \.isLowerBody)
            ? TrainingConstants.defaultLowerBodyIncrementKg
            : exercise.incrementKg
    }

    // MARK: - Lookup

    /// Finds an exercise by exact name, falling back to the first search
    /// result for `fallback` (or `name` if no separate fallback is given),
    /// then to the first exercise whose primary muscle matches.
    static func lookup(
        _ catalogue: WorkoutStore.ExerciseCatalogue, _ name: String, fallback: String? = nil, muscle: Muscle
    ) -> ExerciseInfo? {
        let store = catalogue.store
        let candidates = store.exercises(in: catalogue, matching: name)
        if let exact = candidates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact
        }
        if let first = candidates.first { return first }
        if let fallback, fallback != name {
            let fallbackCandidates = store.exercises(in: catalogue, matching: fallback)
            if let first = fallbackCandidates.first { return first }
        }
        return store.exercises(in: catalogue, muscle: muscle).first { $0.primary.contains(muscle) }
    }
}
