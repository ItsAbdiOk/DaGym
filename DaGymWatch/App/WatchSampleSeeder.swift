import Foundation
import GymCore
import SwiftData

#if DEBUG
/// Seeds the `-dgWatchSample` in-memory store: enough for every spec screen to have data.
@MainActor
enum WatchSampleSeeder {
    static func seed(store: WorkoutStore, now: Date = Date()) {
        let context = store.context
        let library = SampleLibrary()
        for model in library.all { context.insert(model) }
        store.save()
        let (bench, incline, lateral) = (library.bench, library.incline, library.lateral)
        let (pullUp, dip, plank) = (library.pullUp, library.dip, library.plank)
        let (split, run) = (library.split, library.run)

        let push = store.saveRoutine(
            id: nil, name: "Push A", rule: .linearAMRAP(incrementKg: 2.5),
            exercises: [
                RoutineExerciseDraft(exerciseID: bench.id, sets: [
                    PlannedSetDraft(kind: .warmup, targetReps: 5),
                    PlannedSetDraft(kind: .warmup, targetReps: 5),
                    PlannedSetDraft(targetReps: 5, targetWeightKg: 100), PlannedSetDraft(targetReps: 5),
                    PlannedSetDraft(targetReps: 5), PlannedSetDraft(kind: .amrap, targetReps: 5)
                ]),
                RoutineExerciseDraft(exerciseID: incline.id, sets: sets(3, reps: 8, kg: 30)),
                RoutineExerciseDraft(exerciseID: lateral.id, sets: sets(3, reps: 12, kg: 10)),
                RoutineExerciseDraft(
                    exerciseID: pullUp.id, sets: sets(3, reps: 8),
                    overrideRule: .bodyweight(repCeiling: 10, maxSets: 4)
                ),
                RoutineExerciseDraft(
                    exerciseID: dip.id, sets: sets(3, reps: 8, kg: 20), overrideRule: .assisted(stepKg: 5)
                ),
                RoutineExerciseDraft(
                    exerciseID: plank.id, sets: (0..<3).map { _ in PlannedSetDraft(targetSeconds: 45) },
                    overrideRule: .timed(stepSeconds: 10)
                ),
                RoutineExerciseDraft(exerciseID: split.id, sets: sets(3, reps: 16, kg: 24)),
                RoutineExerciseDraft(exerciseID: run.id, sets: [
                    PlannedSetDraft(targetSeconds: 600, targetDistanceMeters: 2000)
                ])
            ]
        )
        let pull = store.saveRoutine(id: nil, name: "Pull A", exercises: [
            RoutineExerciseDraft(exerciseID: library.row.id, sets: sets(4, reps: 8, kg: 60)),
            RoutineExerciseDraft(exerciseID: pullUp.id, sets: sets(3, reps: 8))
        ])
        let legs = store.saveRoutine(id: nil, name: "Legs", exercises: [
            RoutineExerciseDraft(exerciseID: library.squat.id, sets: sets(5, reps: 5, kg: 120))
        ])
        let calendar = Calendar.current
        let today = Weekday(rawValue: calendar.component(.weekday, from: now)) ?? .monday
        var schedule = WeeklySchedule()
        schedule.addRoutine(push.id, to: today)
        schedule.addRoutine(pull.id, to: Weekday(rawValue: (today.rawValue % 7) + 2) ?? .thursday)
        schedule.addRoutine(legs.id, to: Weekday(rawValue: ((today.rawValue + 3) % 7) + 1) ?? .saturday)
        store.saveSchedule(schedule)
        for weeksAgo in 1...2 {
            let date = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now) ?? now
            history(store: store, routine: push, date: date, library: library)
        }
        store.rebuildPersonalRecords()
    }

    private static func sets(_ count: Int, reps: Int, kg: Double? = nil) -> [PlannedSetDraft] {
        (0..<count).map { _ in PlannedSetDraft(targetReps: reps, targetWeightKg: kg) }
    }

    /// One finished Push A session at `date` — 97.5 × 5 bench so today prescribes 100.
    private static func history(
        store: WorkoutStore, routine: RoutineInfo, date: Date, library: SampleLibrary
    ) {
        let (bench, incline, pullUp) = (library.bench, library.incline, library.pullUp)
        let workout = WorkoutModel(
            title: routine.name, startedAt: date, endedAt: date.addingTimeInterval(52 * 60),
            routineID: routine.id, routineName: routine.name
        )
        store.context.insert(workout)
        let rows: [(ExerciseModel, [(Double, Int)])] = [
            (bench, [(97.5, 5), (97.5, 5), (97.5, 5), (97.5, 6)]),
            (incline, [(30, 8), (30, 8), (30, 8)]),
            (pullUp, [(0, 8), (0, 8), (0, 7)])
        ]
        for (order, row) in rows.enumerated() {
            let exercise = WorkoutExerciseModel(
                order: order, routineID: routine.id, exercise: row.0, workout: workout
            )
            store.context.insert(exercise)
            for (setOrder, values) in row.1.enumerated() {
                let set = SetLogModel(
                    order: setOrder, kind: setOrder == 3 && row.0 === bench ? "amrap" : "working",
                    weightKg: values.0, reps: values.1, isCompleted: true,
                    completedAt: date.addingTimeInterval(Double(order * 600 + setOrder * 150)),
                    workoutExercise: exercise
                )
                store.context.insert(set)
            }
        }
        store.save()
    }
}

/// The ten sample exercises, one per set shape plus the Pull A / Legs lifts.
@MainActor
private struct SampleLibrary {
    let bench = make("Bench Press", ["chest"], ["triceps", "delts"], "barbell", bar: "olympic")
    let incline = make("Incline DB Press", ["chest"], ["delts"], "dumbbell", increment: 2)
    let lateral = make("Lateral Raise", ["delts"], [], "dumbbell", increment: 2)
    let pullUp = make("Pull-Up", ["lats"], ["biceps"], "bodyweight", style: "bodyweightReps")
    let dip = make("Assisted Dip", ["chest"], ["triceps"], "machine", style: "assisted", increment: 5)
    let plank = make("Plank", ["abs"], [], "bodyweight", style: "timedHold")
    let split = make("Split Squat", ["quads"], ["glutes"], "dumbbell", increment: 2, perSide: true)
    let run = make("Treadmill Run", ["quads"], ["calves"], "treadmill", style: "cardio")
    let row = make("Barbell Row", ["lats"], ["biceps"], "barbell", bar: "olympic")
    let squat = make("Back Squat", ["quads"], ["glutes"], "barbell", bar: "olympic", increment: 5)

    var all: [ExerciseModel] { [bench, incline, lateral, pullUp, dip, plank, split, run, row, squat] }

    private static func make(
        _ name: String, _ primary: [String], _ secondary: [String], _ equipment: String,
        style: String = "weightReps", bar: String? = nil, increment: Double = 2.5, perSide: Bool = false
    ) -> ExerciseModel {
        ExerciseModel(
            seedID: name.lowercased().replacingOccurrences(of: " ", with: "-"), name: name,
            primaryMuscles: primary, secondaryMuscles: secondary, equipment: equipment,
            loggingStyle: style, isPerSide: perSide, barType: bar, incrementKg: increment, restSeconds: 150
        )
    }
}
#endif
