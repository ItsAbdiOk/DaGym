import Foundation
import GymCore
import SwiftData

/// The routines behind the Upper/Lower, Full Body and 5×5 starter programs, described as data
/// and seeded by name through `RoutineSeeder.seedStarters`. Same lookup, stamping and override
/// rules as the Push/Pull/Legs starters.
extension RoutineSeeder {
    /// A library exercise a starter slot asks for: exact name, search fallback, primary muscle.
    struct Lift {
        var name: String
        var fallback: String?
        var muscle: Muscle

        static let bench = Lift(
            name: "Barbell Bench Press - Medium Grip", fallback: "Bench Press", muscle: .chest
        )
        static let inclineBench = Lift(
            name: "Barbell Incline Bench Press - Medium Grip", fallback: "Incline Bench Press", muscle: .chest
        )
        static let inclineDumbbell = Lift(name: "Incline Dumbbell Press", fallback: nil, muscle: .chest)
        static let row = Lift(name: "Bent Over Barbell Row", fallback: nil, muscle: .lats)
        static let cableRow = Lift(name: "Seated Cable Rows", fallback: "Cable Row", muscle: .lats)
        static let pulldown = Lift(name: "Wide-Grip Lat Pulldown", fallback: "Lat Pulldown", muscle: .lats)
        static let pullups = Lift(name: "Pullups", fallback: "Pull-Up", muscle: .lats)
        static let press = Lift(name: "Barbell Shoulder Press", fallback: nil, muscle: .delts)
        static let dumbbellPress = Lift(name: "Dumbbell Shoulder Press", fallback: nil, muscle: .delts)
        static let curl = Lift(name: "Dumbbell Bicep Curl", fallback: nil, muscle: .biceps)
        static let hammerCurl = Lift(name: "Hammer Curls", fallback: "Hammer Curl", muscle: .biceps)
        static let pushdown = Lift(name: "Triceps Pushdown", fallback: nil, muscle: .triceps)
        static let skullcrusher = Lift(
            name: "EZ-Bar Skullcrusher", fallback: "Skullcrusher", muscle: .triceps
        )
        static let squat = Lift(name: "Barbell Squat", fallback: "Squat", muscle: .quads)
        static let frontSquat = Lift(name: "Front Barbell Squat", fallback: "Front Squat", muscle: .quads)
        static let deadlift = Lift(name: "Barbell Deadlift", fallback: "Deadlift", muscle: .hams)
        static let sumoDeadlift = Lift(name: "Sumo Deadlift", fallback: "Deadlift", muscle: .hams)
        static let romanian = Lift(name: "Romanian Deadlift", fallback: nil, muscle: .hams)
        static let legPress = Lift(name: "Leg Press", fallback: nil, muscle: .quads)
        static let legCurl = Lift(name: "Lying Leg Curls", fallback: "Leg Curl", muscle: .hams)
        static let legExtension = Lift(name: "Leg Extensions", fallback: "Leg Extension", muscle: .quads)
        static let calfRaise = Lift(name: "Standing Calf Raises", fallback: "Calf Raise", muscle: .calves)
        static let plank = Lift(name: "Plank", fallback: nil, muscle: .abs)
        static let legRaise = Lift(name: "Hanging Leg Raise", fallback: nil, muscle: .abs)
    }

    /// One exercise slot in a table-driven starter routine.
    struct Slot {
        var lift: Lift
        var sets: [PlannedSetDraft]
        var supersetGroup: Int?

        init(_ lift: Lift, sets: [PlannedSetDraft], supersetGroup: Int? = nil) {
            self.lift = lift
            self.sets = sets
            self.supersetGroup = supersetGroup
        }
    }

    /// A starter routine described as data: name, routine-level rule and slots.
    struct Spec {
        var name: String
        var rule: ProgressionRule
        var ruleName: String
        var repRangeLow: Int
        var repRangeHigh: Int
        var slots: [Slot]
    }

    private static func working(_ count: Int, reps: Int, high: Int? = nil) -> [PlannedSetDraft] {
        (0..<count).map { _ in PlannedSetDraft(kind: .working, targetReps: reps, targetRepsHigh: high) }
    }

    private static func hold(_ count: Int, seconds: Int) -> [PlannedSetDraft] {
        (0..<count).map { _ in PlannedSetDraft(kind: .working, targetSeconds: seconds) }
    }

    private static let warmupRamp = [
        PlannedSetDraft(kind: .warmup, targetReps: 8), PlannedSetDraft(kind: .warmup, targetReps: 5)
    ]

    /// Seeds one table-driven routine; false (and nothing written) if any of its exercises
    /// can't be found.
    static func seed(
        _ spec: Spec, store: WorkoutStore, catalogue: WorkoutStore.ExerciseCatalogue
    ) -> Bool {
        var exercises: [RoutineExerciseDraft] = []
        for slot in spec.slots {
            let lift = slot.lift
            guard let exercise = lookup(catalogue, lift.name, fallback: lift.fallback, muscle: lift.muscle)
            else {
                return false
            }
            exercises.append(RoutineExerciseDraft(
                exerciseID: exercise.id, supersetGroup: slot.supersetGroup, sets: slot.sets,
                overrideRule: starterOverride(for: exercise, routineRule: spec.rule)
            ))
        }
        let routine = store.saveRoutine(
            id: nil, name: spec.name, progressionRule: spec.ruleName,
            repRangeLow: spec.repRangeLow, repRangeHigh: spec.repRangeHigh, rule: spec.rule,
            exercises: exercises
        )
        stamp(routine, store: store)
        return true
    }

    static func programRoutineSpecs() -> [Spec] {
        upperLowerSpecs() + fullBodySpecs() + fiveByFiveSpecs()
    }

    private static func doubleProgression(low: Int, high: Int, slots: [Slot], name: String) -> Spec {
        Spec(
            name: name,
            rule: .doubleProgression(
                low: low, high: high, incrementKg: TrainingConstants.defaultUpperBodyIncrementKg
            ),
            ruleName: "doubleProgression", repRangeLow: low, repRangeHigh: high, slots: slots
        )
    }

    private static func linear(reps: Int, slots: [Slot], name: String) -> Spec {
        Spec(
            name: name, rule: .linear(incrementKg: TrainingConstants.defaultUpperBodyIncrementKg),
            ruleName: "linear", repRangeLow: reps, repRangeHigh: reps, slots: slots
        )
    }

    private static func upperLowerSpecs() -> [Spec] {
        [
            doubleProgression(low: 6, high: 10, slots: [
                Slot(.bench, sets: warmupRamp + working(4, reps: 6, high: 10)),
                Slot(.row, sets: working(4, reps: 6, high: 10)),
                Slot(.press, sets: working(3, reps: 6, high: 10)),
                Slot(.pulldown, sets: working(3, reps: 8, high: 12)),
                Slot(.curl, sets: working(3, reps: 10, high: 12), supersetGroup: 1),
                Slot(.pushdown, sets: working(3, reps: 10, high: 12), supersetGroup: 1)
            ], name: "Upper A"),
            linear(reps: 5, slots: [
                Slot(.squat, sets: warmupRamp + working(4, reps: 5)),
                Slot(.romanian, sets: working(3, reps: 8)),
                Slot(.legPress, sets: working(3, reps: 10)),
                Slot(.calfRaise, sets: working(4, reps: 12)),
                Slot(.plank, sets: hold(3, seconds: 45))
            ], name: "Lower A"),
            doubleProgression(low: 8, high: 12, slots: [
                Slot(.inclineDumbbell, sets: working(4, reps: 8, high: 12)),
                Slot(.cableRow, sets: working(4, reps: 8, high: 12)),
                Slot(.dumbbellPress, sets: working(3, reps: 8, high: 12)),
                Slot(.pullups, sets: working(3, reps: 8)),
                Slot(.hammerCurl, sets: working(3, reps: 10, high: 12), supersetGroup: 1),
                Slot(.skullcrusher, sets: working(3, reps: 10, high: 12), supersetGroup: 1)
            ], name: "Upper B"),
            linear(reps: 5, slots: [
                Slot(.deadlift, sets: warmupRamp + working(3, reps: 5)),
                Slot(.frontSquat, sets: working(3, reps: 6)),
                Slot(.legCurl, sets: working(3, reps: 10)),
                Slot(.legExtension, sets: working(3, reps: 12)),
                Slot(.legRaise, sets: working(3, reps: 12))
            ], name: "Lower B")
        ]
    }

    private static func fullBodySpecs() -> [Spec] {
        [
            doubleProgression(low: 5, high: 8, slots: [
                Slot(.squat, sets: warmupRamp + working(3, reps: 5, high: 8)),
                Slot(.bench, sets: working(3, reps: 5, high: 8)),
                Slot(.row, sets: working(3, reps: 5, high: 8)),
                Slot(.plank, sets: hold(2, seconds: 45))
            ], name: "Full Body A"),
            doubleProgression(low: 5, high: 8, slots: [
                Slot(.deadlift, sets: warmupRamp + working(3, reps: 5, high: 8)),
                Slot(.press, sets: working(3, reps: 5, high: 8)),
                Slot(.pullups, sets: working(3, reps: 6)),
                Slot(.legRaise, sets: working(2, reps: 12))
            ], name: "Full Body B"),
            doubleProgression(low: 5, high: 8, slots: [
                Slot(.legPress, sets: working(3, reps: 8, high: 12)),
                Slot(.inclineDumbbell, sets: working(3, reps: 8, high: 12)),
                Slot(.cableRow, sets: working(3, reps: 8, high: 12)),
                Slot(.calfRaise, sets: working(3, reps: 12))
            ], name: "Full Body C")
        ]
    }

    /// Three compound barbell lifts per day, 5×5 each, on a linear rule — no planned warm-ups,
    /// the warm-up generator ramps from the working weight.
    private static func fiveByFiveSpecs() -> [Spec] {
        let fiveByFive = working(5, reps: 5)
        return [
            linear(reps: 5, slots: [
                Slot(.squat, sets: fiveByFive), Slot(.bench, sets: fiveByFive), Slot(.row, sets: fiveByFive)
            ], name: "5×5 A"),
            linear(reps: 5, slots: [
                Slot(.squat, sets: fiveByFive), Slot(.press, sets: fiveByFive),
                Slot(.deadlift, sets: fiveByFive)
            ], name: "5×5 B"),
            linear(reps: 5, slots: [
                Slot(.frontSquat, sets: fiveByFive), Slot(.inclineBench, sets: fiveByFive),
                Slot(.sumoDeadlift, sets: fiveByFive)
            ], name: "5×5 C")
        ]
    }
}
