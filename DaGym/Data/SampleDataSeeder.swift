import Foundation
import GymCore
import SwiftData

/// Seeds a trial-friendly slice of history — eight weeks of finished workouts cycling the
/// always-present Push/Pull/Legs starters — so a first-time user (or an App Review pass) can see
/// what a trained-in DaGym looks like before logging a single set themselves (OpenGym parity 84
/// / Adopt-now 29). Every workout it writes is tagged `sourceDevice = "sample"` so `clear` can
/// wipe exactly what it added and nothing else.
@MainActor
enum SampleDataSeeder {
    /// `WorkoutModel.sourceDevice` tag for every workout this seeder inserts.
    static let sourceTag = "sample"

    private static let routineNames = ["Push A", "Pull B", "Legs"]
    /// Weekday offsets (from the start of a 7-day block, 0 = oldest day in the block) the three
    /// routines land on — spread across the week rather than back to back.
    private static let dayOffsets = [0, 2, 4]
    private static let weeks = 8

    /// No-ops if the starter routines aren't present (a store that never seeded them, or had
    /// them deleted) — sample data should never invent routines of its own.
    static func seed(store: WorkoutStore, preferences: Preferences, now: Date = Date()) {
        let routines = store.routines()
        let ordered = routineNames.compactMap { name in routines.first { $0.name == name } }
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
    /// banner. Leaves the starter routines themselves alone; they're shared with the real app,
    /// not sample-only, and stay seeded regardless.
    static func clear(store: WorkoutStore, preferences: Preferences) {
        let predicate = #Predicate<WorkoutModel> { $0.sourceDevice == "sample" }
        let models = (try? store.context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        for model in models { store.context.delete(model) }
        store.save()
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

        var entries: [WorkoutExerciseModel] = []
        for (order, exercise) in routine.exercises.enumerated() {
            guard let exerciseModel = store.fetchExerciseModel(id: exercise.id) else { continue }
            let entry = WorkoutExerciseModel(order: order, exercise: exerciseModel, workout: workout)
            store.context.insert(entry)
            let sets = plausibleSets(for: exercise, sessionIndex: sessionIndex, at: date, entry: entry)
            entry.sets = sets
            for set in sets { store.context.insert(set) }
            entries.append(entry)
        }
        workout.exercises = entries
    }

    /// A gentle, plausible progression: three working sets, reps stepping down across the set
    /// (the usual "same weight, effort climbs" shape), weight nudged up by the exercise's own
    /// increment roughly every third session so the charts have a visible trend.
    private static func plausibleSets(
        for exercise: ExerciseInfo, sessionIndex: Int, at date: Date, entry: WorkoutExerciseModel
    ) -> [SetLogModel] {
        let bumps = Double(sessionIndex / 3)
        let baseWeight = max(exercise.incrementKg * 4, exercise.incrementKg > 0 ? 20 : 0)
        let weight = exercise.incrementKg > 0 ? baseWeight + bumps * exercise.incrementKg : 0
        let setCount = 3
        return (0..<setCount).map { index in
            SetLogModel(
                order: index, kind: SetKind.working.rawValue, weightKg: weight,
                reps: max(6, 9 - index), isCompleted: true, completedAt: date, workoutExercise: entry
            )
        }
    }
}
