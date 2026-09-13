import Foundation
import GymCore

/// Realistic sample content matching the design mockups.
@MainActor
enum SampleData {
    static let bench = ExerciseInfo(
        name: "Bench Press (Barbell)", primary: [.chest], secondary: [.delts, .triceps],
        equipment: "Barbell", incrementKg: 2.5, restSeconds: 150, isFavorite: true,
        bestE1RM: 102.5, bestSet: "82.5×8", sessions: 37,
        instructions: "Set your grip about one and a half shoulder widths. Squeeze the shoulder blades "
            + "down and back, take the bar out, lower to the lower chest, then press back over the "
            + "shoulders."
    )
    static let inclineDB = ExerciseInfo(
        name: "Incline DB Press", primary: [.chest], secondary: [.delts],
        equipment: "Dumbbell", incrementKg: 2, restSeconds: 120, bar: nil, bestE1RM: 34, sessions: 22
    )
    static let overhead = ExerciseInfo(
        name: "Overhead Press", primary: [.delts], secondary: [.triceps, .traps],
        equipment: "Barbell", incrementKg: 2.5, restSeconds: 150, bestE1RM: 60, sessions: 30
    )
    static let cableFly = ExerciseInfo(
        name: "Cable Fly", primary: [.chest], equipment: "Cable", incrementKg: 2.5, restSeconds: 90,
        bar: nil, isFavorite: true, sessions: 3
    )
    static let tricepsRope = ExerciseInfo(
        name: "Triceps Rope Pushdown", primary: [.triceps], equipment: "Cable", incrementKg: 2.5,
        restSeconds: 90, bar: nil, sessions: 28
    )
    static let weightedDip = ExerciseInfo(
        name: "Weighted Dip", primary: [.chest], secondary: [.triceps], equipment: "Bodyweight",
        incrementKg: 2.5, restSeconds: 150, bar: nil, sessions: 12, loggingStyle: .weightedBodyweight
    )
    static let deficitPushup = ExerciseInfo(
        name: "Deficit Push-up", primary: [.chest], secondary: [.triceps], equipment: "Bodyweight",
        incrementKg: 0, restSeconds: 90, bar: nil, isCustom: true, sessions: 4, loggingStyle: .bodyweightReps
    )
    static let plank = ExerciseInfo(
        name: "Plank", primary: [.abs], secondary: [.obliques], equipment: "Bodyweight",
        incrementKg: 0, restSeconds: 60, bar: nil, sessions: 40, loggingStyle: .timedHold
    )
    static let squat = ExerciseInfo(
        name: "Back Squat", primary: [.quads], secondary: [.glutes, .lowerBack], equipment: "Barbell",
        incrementKg: 5, restSeconds: 180, bestE1RM: 140, sessions: 41
    )
    static let deadlift = ExerciseInfo(
        name: "Deadlift", primary: [.hams], secondary: [.glutes, .lowerBack, .lats], equipment: "Barbell",
        incrementKg: 5, restSeconds: 180, bestE1RM: 170, sessions: 35
    )
    static let pullup = ExerciseInfo(
        name: "Pull-up", primary: [.lats], secondary: [.biceps], equipment: "Bodyweight",
        incrementKg: 0, restSeconds: 120, bar: nil, sessions: 44, loggingStyle: .bodyweightReps
    )
    static let row = ExerciseInfo(
        name: "Barbell Row", primary: [.lats], secondary: [.biceps, .lowerBack], equipment: "Barbell",
        incrementKg: 2.5, restSeconds: 120, bestE1RM: 95, sessions: 26
    )
    static let curl = ExerciseInfo(
        name: "Dumbbell Curl", primary: [.biceps], secondary: [.forearms], equipment: "Dumbbell",
        incrementKg: 2, restSeconds: 60, bar: nil, sessions: 19
    )
    static let legCurl = ExerciseInfo(
        name: "Lying Leg Curl", primary: [.hams], equipment: "Machine", incrementKg: 2.5,
        restSeconds: 90, bar: nil, sessions: 17
    )
    static let calfRaise = ExerciseInfo(
        name: "Standing Calf Raise", primary: [.calves], equipment: "Machine", incrementKg: 5,
        restSeconds: 60, bar: nil, sessions: 21
    )

    static let library: [ExerciseInfo] = [
        bench, inclineDB, cableFly, weightedDip, deficitPushup, overhead, tricepsRope, plank,
        squat, deadlift, pullup, row, curl, legCurl, calfRaise
    ]

    static let pushA = RoutineInfo(
        name: "Push A", exercises: [bench, inclineDB, overhead, cableFly, tricepsRope],
        setCount: 18, estimatedMinutes: 52, progressionRule: "Double progression · 6–8 reps",
        progressionDetail: "Hit 8 reps on every set and the weight goes up one increment next time.",
        weekLabel: "Week 3 of 6"
    )
    static let pullB = RoutineInfo(
        name: "Pull B", exercises: [deadlift, pullup, row, curl], setCount: 16, estimatedMinutes: 48,
        progressionRule: "Linear · +2.5 kg",
        progressionDetail: "Hit every rep and the weight goes up next time."
    )
    static let legs = RoutineInfo(
        name: "Legs", exercises: [squat, legCurl, calfRaise, plank], setCount: 20, estimatedMinutes: 61,
        progressionRule: "Linear · +5 kg",
        progressionDetail: "Hit every rep and the weight goes up next time."
    )
    static let routines: [RoutineInfo] = [pushA, pullB, legs]

    static func makeSession() -> WorkoutSession {
        let benchEntry = WorkoutExerciseEntry(
            exercise: bench,
            sets: [
                SetEntry(kind: .warmup, weightKg: 40, reps: 10, isDone: true),
                SetEntry(kind: .warmup, weightKg: 60, reps: 5, isDone: true),
                SetEntry(
                    weightKg: 82.5, reps: 8, effort: Effort(rpe: 8), isDone: true,
                    previousWeightKg: 80, previousReps: 8
                ),
                SetEntry(weightKg: 82.5, reps: 8, previousWeightKg: 80, previousReps: 8),
                SetEntry(kind: .amrap, weightKg: 75, reps: 11, previousWeightKg: 75, previousReps: 11)
            ],
            whyTitle: "Why 82.5 kg?",
            whyBody: "You pressed 80 × 8 at RPE 7 last Tuesday — one step up keeps you near the effort "
                + "you're aiming for. A suggestion, not a rule.",
            lastSessions: ["80 × 8,8,7", "77.5 × 8,8,8", "77.5 × 8,7,7"],
            sparkline: [96, 97, 99, 98.5, 100, 102.5]
        )
        let incline = WorkoutExerciseEntry(
            exercise: inclineDB,
            sets: (0..<3).map { _ in
                SetEntry(weightKg: 26, reps: 10, previousWeightKg: 24, previousReps: 10)
            },
            supersetGroup: 1
        )
        let rope = WorkoutExerciseEntry(
            exercise: tricepsRope,
            sets: [
                SetEntry(weightKg: 30, reps: 12, previousWeightKg: 30, previousReps: 12),
                SetEntry(weightKg: 30, reps: 12, previousWeightKg: 30, previousReps: 12),
                SetEntry(kind: .drop, weightKg: 30, reps: 12, previousWeightKg: 30, previousReps: 12)
            ],
            supersetGroup: 1
        )
        let plankEntry = WorkoutExerciseEntry(
            exercise: plank,
            sets: (0..<3).map { _ in SetEntry(weightKg: 0, reps: 0, targetSeconds: 60) }
        )
        let ohp = WorkoutExerciseEntry(
            exercise: overhead,
            sets: (0..<4).map { _ in
                SetEntry(weightKg: 47.5, reps: 6, effort: Effort(rpe: 8), isDone: true)
            }
        )
        let session = WorkoutSession(
            title: "Push A", subtitle: "Week 3 · Day 2",
            startedAt: Date().addingTimeInterval(-32 * 60 - 18),
            exercises: [benchEntry, incline, rope, plankEntry, ohp]
        )
        session.restRemaining = 92
        session.restTotal = 150
        session.restNextWeightKg = 82.5
        session.restNextReps = 8
        session.prBanner = PersonalRecordInfo(
            exerciseName: "Bench", line: "Best bench e1RM yet: 102.5 kg, up 2.5 from August."
        )
        return session
    }

    static let history: [WorkoutRecord] = {
        let cal = Calendar.current
        let now = Date()
        func day(_ ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: now) ?? now }
        return [
            WorkoutRecord(
                title: "Push A", date: day(0), durationMinutes: 52,
                volumeKg: 6840, sets: 18, prCount: 2
            ),
            WorkoutRecord(
                title: "Legs", date: day(2), durationMinutes: 61,
                volumeKg: 9120, sets: 20
            ),
            WorkoutRecord(
                title: "Pull B", date: day(4), durationMinutes: 48,
                volumeKg: 5480, sets: 16
            ),
            WorkoutRecord(
                title: "Push A", date: day(7), durationMinutes: 50,
                volumeKg: 6610, sets: 18
            ),
            WorkoutRecord(
                title: "Legs", date: day(9), durationMinutes: 58,
                volumeKg: 8900, sets: 20
            ),
            WorkoutRecord(
                title: "Pull B", date: day(11), durationMinutes: 47,
                volumeKg: 5390, sets: 16, prCount: 1
            )
        ]
    }()

    static let recoveryMap: [Muscle: Double] = [
        .chest: 0.9, .delts: 0.7, .triceps: 0.6, .abs: 0.2, .quads: 0.1, .hams: 0.15, .glutes: 0.1,
        .lats: 0.2, .biceps: 0.3, .lowerBack: 0.2, .calves: 0.05, .forearms: 0.3, .traps: 0.2, .obliques: 0.1
    ]

    static let e1rmSeries: [(month: String, value: Double)] = [
        ("Apr", 90), ("May", 92.5), ("Jun", 96), ("Jul", 95), ("Aug", 100), ("Sep", 102.5)
    ]
}
