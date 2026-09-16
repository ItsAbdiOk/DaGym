import Foundation
import GymCore
import SwiftData

/// Seeds a trial-friendly slice of history — eight weeks of finished workouts cycling the
/// Push/Pull/Legs starters, which it seeds first if the store doesn't have them — so a
/// first-time user (or an App Review pass) can see what a trained-in DaGym looks like before
/// logging a single set themselves (OpenGym parity 84 / Adopt-now 29). Every workout it writes
/// is tagged `sourceDevice = "sample"` so `clear` can wipe exactly what it added and nothing
/// else; the trio goes with it when nothing of the lifter's own points at it.
@MainActor
enum SampleDataSeeder {
    /// `WorkoutModel.sourceDevice` tag for every workout this seeder inserts.
    static let sourceTag = "sample"

    private static let routineNames = RoutineSeeder.pushPullLegsNames
    /// Weekday offsets (from the start of a 7-day block, 0 = oldest day in the block) the three
    /// routines land on — spread across the week rather than back to back, with the newest
    /// session yesterday so the recovery map, "this week" and the streak all have something
    /// recent to show (offsets 0/2/4 left the newest session two days out and every muscle
    /// fresh).
    private static let dayOffsets = [1, 3, 5]
    private static let weeks = 8

    /// Seeds the Push/Pull/Legs trio when the store doesn't have it (the app ships no routines),
    /// then the history. No-ops if a day can't be built from the library — sample data never
    /// invents routines of its own.
    static func seed(store: WorkoutStore, preferences: Preferences, now: Date = Date()) {
        RoutineSeeder.seedStarters(routineNames, store: store)
        let routines = store.routines()
        // By starter id first, as `seedStarters` counts presence: a renamed "Push A" is still
        // the trio's push day, and matching by name alone made this a silent no-op for it.
        let live = store.fetch(FetchDescriptor<RoutineModel>()).filter { !$0.isMergedAway }
        let ordered = routineNames.compactMap { name -> RoutineInfo? in
            let byStarterID = RoutineSeeder.starterIDs[name].flatMap { id in
                live.first { $0.importedFromID == id }
            }
            let model = byStarterID ?? live.first { $0.name == name }
            return model.flatMap { model in routines.first { $0.id == model.id } }
        }
        guard ordered.count == routineNames.count else { return }

        let calendar = Calendar.current
        var sessionIndex = 0
        for weekAgo in stride(from: weeks - 1, through: 0, by: -1) {
            for (offset, routine) in zip(dayOffsets, ordered) {
                let daysAgo = weekAgo * 7 + (6 - offset)
                guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
                insertWorkout(routine: routine, at: date, sessionIndex: sessionIndex, store: store)
                sessionIndex += 1
            }
        }
        store.save()
        store.rebuildPersonalRecords()
        preferences.sampleDataMode = true
    }

    /// Deletes every workout this seeder wrote and clears the flag — Home's "Sample data · Clear"
    /// banner. The trio it seeded goes too, once the sample workouts no longer point at it —
    /// unless the lifter made a day theirs in the meantime (ran it, scheduled it, put it in a
    /// program or renamed it; `RoutineSeeder.untouchedStarters`), in which case it stays.
    static func clear(store: WorkoutStore, preferences: Preferences) {
        let predicate = #Predicate<WorkoutModel> { $0.sourceDevice == "sample" }
        for model in store.fetch(FetchDescriptor(predicate: predicate)) { store.context.delete(model) }
        store.save()
        RoutineSeeder.deleteUntouchedStarters(store: store, among: routineNames)
        store.rebuildPersonalRecords()
        preferences.sampleDataMode = false
    }

    private static func insertWorkout(
        routine: RoutineInfo, at date: Date, sessionIndex: Int, store: WorkoutStore
    ) {
        let workout = WorkoutModel(
            title: routine.name, startedAt: date, endedAt: date.addingTimeInterval(52 * 60),
            isBackfilled: true, routineID: routine.id, routineName: routine.name, sourceDevice: sourceTag
        )
        store.context.insert(workout)
        let drafts = store.routineDrafts(id: routine.id)?.drafts ?? []

        // Children are linked through the `workout:`/`workoutExercise:` inverses only. Assigning
        // the parent's array as well makes SwiftData rebuild a relationship it is already mid-way
        // through updating, which traps (the trap `restoreWorkout` was rewritten to avoid).
        for (order, exercise) in routine.exercises.enumerated() {
            guard let exerciseModel = store.fetchExerciseModel(id: exercise.id) else { continue }
            let entry = WorkoutExerciseModel(order: order, exercise: exerciseModel, workout: workout)
            store.context.insert(entry)
            let planned = drafts.first { $0.exerciseID == exercise.id }?.sets.filter { $0.kind == .working }
            let sets = plausibleSets(
                for: exercise, planned: planned ?? [], sessionIndex: sessionIndex, at: date, entry: entry
            )
            for set in sets {
                store.context.insert(set)
            }
        }
        workout.stampTotals()
    }

    /// A gentle, plausible progression on the routine's own plan: every working set it
    /// prescribes, at (or, on the last set, one under) its rep target, weight nudged up by the
    /// exercise's increment roughly every third session so the charts have a visible trend.
    /// Loads start from `startingWeightKg` — an intermediate lifter's numbers, not the bare
    /// increment, so the history reads as real training rather than an empty bar. Holds log
    /// seconds, and an RPE that drifts session to session rides on every set so the effort
    /// surfaces have data that isn't a flat line.
    private static func plausibleSets(
        for exercise: ExerciseInfo, planned: [PlannedSetDraft], sessionIndex: Int, at date: Date,
        entry: WorkoutExerciseModel
    ) -> [SetLogModel] {
        let bumps = Double(sessionIndex / 3)
        let base = startingWeightKg(for: exercise)
        let bumpKg = exercise.loggingStyle == .weightedBodyweight ? 1.25 : max(exercise.incrementKg, 2.5)
        let weight = base > 0 ? base + bumps * bumpKg : 0
        let setCount = planned.isEmpty ? 3 : planned.count
        let effortDrift = [0.0, 0.5, -0.5, 0.0][sessionIndex % 4]
        let isHold = exercise.loggingStyle == .timedHold
        return (0..<setCount).map { index in
            let plan = planned.indices.contains(index) ? planned[index] : PlannedSetDraft()
            let target = plan.targetRepsHigh ?? plan.targetReps ?? 8
            // Reps: the target, dipping one short on the final set every other session — the
            // "almost there" shape that keeps double progression honest without stalling it.
            let short = index == setCount - 1 && sessionIndex.isMultiple(of: 2) ? 1 : 0
            let hold = (plan.targetSeconds ?? 45) + 5 * Int(bumps) - 5 * index
            return SetLogModel(
                order: index, kind: SetKind.working.rawValue, weightKg: isHold ? 0 : weight,
                reps: isHold ? 0 : max(1, target - short),
                durationSeconds: isHold ? max(20, hold) : nil,
                rpe: min(10, max(6, Double(7 + min(index, 2)) + effortDrift)), isCompleted: true,
                completedAt: date, workoutExercise: entry
            )
        }
    }

    /// Where the first session's working weight sits, by what the exercise loads. Bodyweight
    /// work starts at zero (reps carry the progression), holds carry no weight at all.
    static func startingWeightKg(for exercise: ExerciseInfo) -> Double {
        switch exercise.loggingStyle {
        case .bodyweightReps, .timedHold, .cardio, .assisted: return 0
        case .weightedBodyweight: return 5
        case .weightReps: return loadedStartingWeightKg(for: exercise)
        }
    }

    private static let barbellStartKg: [Muscle: Double] = [
        .quads: 80, .glutes: 80, .hams: 100, .lowerBack: 100, .chest: 80, .lats: 60, .traps: 60
    ]

    private static func loadedStartingWeightKg(for exercise: ExerciseInfo) -> Double {
        let muscle = exercise.primary.first ?? .chest
        let equipment = exercise.equipment.lowercased()
        if equipment.contains("barbell") { return barbellStartKg[muscle] ?? 40 }
        if equipment.contains("dumbbell") { return [.biceps, .triceps, .delts].contains(muscle) ? 12 : 24 }
        if equipment.contains("cable") { return 25 }
        if equipment.contains("machine") || equipment.contains("smith") {
            return [.quads, .hams, .calves].contains(muscle) ? 60 : 40
        }
        return max(exercise.incrementKg * 4, 20)
    }
}
