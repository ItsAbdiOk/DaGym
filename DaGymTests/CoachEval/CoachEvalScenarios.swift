import Foundation
import GymCore

@testable import DaGym

/// The eight lifters the eval runs, in the order the report lists them. Each seeds 3–8 weeks
/// of history relative to the builder's fixed `now`; weights climb by a fixed step per week
/// unless the scenario is about them not climbing.
enum CoachEvalScenarios {
    typealias Entry = CoachEvalStoreBuilder.Entry
    typealias Lift = CoachEvalLift

    static let all: [CoachEvalScenario] = [
        beginnerTwoDay, plateauedBench, underRecovered, returningAfterLayoff,
        homeDumbbells, cutKeepStrength, squatForecast, ambiguousRoutine
    ]

    /// `count` working sets of `name` at `kg` × `reps`.
    private static func sets(
        _ name: String, _ count: Int, _ kg: Double, _ reps: Int, rpe: Double = 8
    ) -> Entry {
        Entry(name, count: count, kg: kg, reps: reps, rpe: rpe)
    }

    /// `start` in the oldest of `weeks` weeks, up `step` each week to the newest.
    private static func up(_ start: Double, _ step: Double, _ weekAgo: Int, of weeks: Int) -> Double {
        start + step * Double(weeks - 1 - weekAgo)
    }

    // MARK: - 1. Beginner, two days a week, three weeks in

    static let beginnerTwoDay = CoachEvalScenario(
        id: "beginner-2day", title: "Beginner, 2-day full body, asks for a routine",
        prompt: "I've been going twice a week for three weeks doing the same few lifts. "
            + "Can you build me a proper 2-day full body routine to follow from here?",
        goal: .general, experience: .beginner, weeklyGoal: 2, sessionsPerWeek: 2,
        volumeExpectation: .atLeastRecent,
        evidenceKeywords: [["squat"], ["bench"], ["row"], ["two", "2-day", "2 day", "twice"]]
    ) { builder in
        builder.profile(name: "Commercial gym", equipment: Lift.gymEquipment)
        builder.bodyweight(kg: 74, daysAgo: 2)
        try builder.weeks(3, dayShifts: [1, 4], titles: ["Full body"]) { week, _ in
            [
                sets(Lift.squat, 3, up(40, 5, week, of: 3), 8, rpe: 7),
                sets(Lift.bench, 3, up(30, 2.5, week, of: 3), 8, rpe: 7),
                sets(Lift.dbRow, 3, up(12, 2, week, of: 3), 10, rpe: 7)
            ]
        }
    }

    // MARK: - 2. Intermediate upper/lower with a bench stuck for four weeks

    static let plateauedBench = CoachEvalScenario(
        id: "plateau-bench", title: "4-day upper/lower, bench stalled 4 weeks",
        prompt: "My bench has been stuck for a month while everything else moves. What should I change?",
        goal: .strength, experience: .intermediate, weeklyGoal: 4, sessionsPerWeek: 4,
        volumeExpectation: .any,
        evidenceKeywords: [["stall", "stuck", "plateau", "same weight", "hasn't moved"], ["90"], ["week"]]
    ) { builder in
        builder.profile(name: "Commercial gym", equipment: Lift.gymEquipment)
        builder.bodyweight(kg: 82, daysAgo: 3)
        try builder.weeks(
            8, dayShifts: [1, 2, 4, 5], titles: ["Upper", "Lower"], saveRoutines: true
        ) { week, day in
            // Bench climbs to 90 over the first four weeks, then sits at 90×5 while the
            // effort creeps up; every other lift keeps its step.
            let benchKg = week >= 4 ? up(80, 2.5, week, of: 8) : 90
            let benchRPE = week >= 4 ? 8 : min(10, 9 + Double(3 - week) * 0.5)
            return day.isMultiple(of: 2)
                ? [
                    sets(Lift.bench, 5, benchKg, 5, rpe: benchRPE),
                    sets(Lift.row, 4, up(70, 2.5, week, of: 8), 6),
                    sets(Lift.press, 3, up(45, 1.25, week, of: 8), 6),
                    sets(Lift.pulldown, 3, up(60, 2.5, week, of: 8), 10)
                ]
                : [
                    sets(Lift.squat, 4, up(110, 2.5, week, of: 8), 5),
                    sets(Lift.rdl, 3, up(100, 2.5, week, of: 8), 8),
                    sets(Lift.legPress, 3, up(160, 5, week, of: 8), 10),
                    sets(Lift.legCurl, 3, up(45, 2.5, week, of: 8), 12)
                ]
        }
    }

    // MARK: - 3. Under-recovered: sets climbing, RPE 9–10, sessions getting shorter

    static let underRecovered = CoachEvalScenario(
        id: "under-recovered", title: "Volume climbing, RPE 9–10, sessions shortening",
        prompt: "Plan next week's training for me.",
        goal: .hypertrophy, experience: .intermediate, weeklyGoal: 4, sessionsPerWeek: 4,
        volumeExpectation: .atMostRecent,
        evidenceKeywords: [
            ["fatigue", "tired", "recover", "run down", "beat up"], ["rpe", "effort", "hard", "grind"],
            ["deload", "easier", "back off", "lighter", "pull back", "reduce"]
        ]
    ) { builder in
        builder.profile(name: "Commercial gym", equipment: Lift.gymEquipment)
        builder.bodyweight(kg: 85, daysAgo: 1)
        let shrinking: (Int) -> Int = { week in 75 - (7 - week) * 3 }
        try builder.weeks(
            8, dayShifts: [1, 2, 4, 5], titles: ["Upper", "Lower"], minutes: shrinking, saveRoutines: true,
            entries: { week, day in
                let count = week >= 5 ? 3 : (week >= 2 ? 4 : 6)
                let rpe: Double = week >= 4 ? 8 : (week >= 2 ? 9 : 10)
                return day.isMultiple(of: 2)
                    ? [
                        sets(Lift.bench, count, up(85, 1.25, week, of: 8), 8, rpe: rpe),
                        sets(Lift.row, count, up(75, 1.25, week, of: 8), 8, rpe: rpe),
                        sets(Lift.press, count, 50, 8, rpe: rpe),
                        sets(Lift.curl, count, 35, 10, rpe: rpe),
                        sets(Lift.pushdown, count, 30, 12, rpe: rpe)
                    ]
                    : [
                        sets(Lift.squat, count, up(120, 1.25, week, of: 8), 6, rpe: rpe),
                        sets(Lift.rdl, count, 110, 8, rpe: rpe),
                        sets(Lift.legPress, count, 200, 10, rpe: rpe),
                        sets(Lift.legCurl, count, 50, 12, rpe: rpe)
                    ]
            }
        )
    }

    // MARK: - 4. Back after three weeks off

    static let returningAfterLayoff = CoachEvalScenario(
        id: "returning-3wk", title: "Returning after 3 weeks off",
        prompt: "I've been away for three weeks with work. How should I get back into training this week?",
        goal: .hypertrophy, experience: .intermediate, weeklyGoal: 3, sessionsPerWeek: 3,
        volumeExpectation: .any, weightBand: -30...0, bestsWindowDays: 56,
        evidenceKeywords: [
            ["three weeks", "3 weeks", "weeks off", "break", "layoff", "away", "time off"],
            ["lighter", "ease", "back off", "reduce", "%", "below", "under"]
        ]
    ) { builder in
        builder.profile(name: "Commercial gym", equipment: Lift.gymEquipment)
        builder.bodyweight(kg: 78, daysAgo: 22)
        // Five weeks of full body, then nothing for the last three. The routine stays saved.
        try builder.routine("Full body", entries: [
            sets(Lift.squat, 3, up(90, 2.5, 3, of: 8), 6), sets(Lift.bench, 3, up(70, 2.5, 3, of: 8), 6),
            sets(Lift.row, 3, up(65, 2.5, 3, of: 8), 8), sets(Lift.rdl, 3, up(85, 2.5, 3, of: 8), 8)
        ])
        for week in (3..<8).reversed() {
            for (day, shift) in [1.0, 3, 5].enumerated() {
                let push = day == 1
                    ? sets(Lift.press, 3, 45, 6)
                    : sets(Lift.bench, 3, up(70, 2.5, week, of: 8), 6)
                try builder.session(
                    daysAgo: Double(week) * 7 + shift, title: "Full body", minutes: 60,
                    entries: [
                        sets(Lift.squat, 3, up(90, 2.5, week, of: 8), 6),
                        push,
                        sets(Lift.row, 3, up(65, 2.5, week, of: 8), 8),
                        sets(Lift.rdl, 3, up(85, 2.5, week, of: 8), 8)
                    ]
                )
            }
        }
    }

    // MARK: - 5. Home: dumbbells and bands only

    static let homeDumbbells = CoachEvalScenario(
        id: "home-dumbbells", title: "Dumbbells + bands at home, wants a new 3-day routine",
        prompt: "I only have adjustable dumbbells up to 30 kg and some bands at home. "
            + "Give me a new 3-day routine so I keep progressing.",
        goal: .hypertrophy, experience: .intermediate, weeklyGoal: 3, sessionsPerWeek: 1,
        volumeExpectation: .any,
        evidenceKeywords: [["dumbbell"], ["band"], ["30"]]
    ) { builder in
        builder.profile(name: "Home", equipment: Lift.homeEquipment, restrictsMachines: true)
        builder.bodyweight(kg: 70, daysAgo: 1)
        try builder.weeks(6, dayShifts: [1, 3, 5], titles: ["Home A", "Home B"]) { week, day in
            day.isMultiple(of: 2)
                ? [
                    sets(Lift.dbBench, 3, up(20, 1, week, of: 6), 10),
                    sets(Lift.goblet, 3, up(20, 1, week, of: 6), 12),
                    sets(Lift.dbRow, 3, up(22, 1, week, of: 6), 10),
                    sets(Lift.bandPullApart, 3, 0, 15, rpe: 7)
                ]
                : [
                    sets(Lift.dbPress, 3, up(12, 1, week, of: 6), 10),
                    sets(Lift.dbRDL, 3, up(22, 1, week, of: 6), 10),
                    sets(Lift.dbLunge, 3, up(14, 1, week, of: 6), 10),
                    sets(Lift.pushUp, 3, 0, 15)
                ]
        }
    }

    // MARK: - 6. A cut: bodyweight trending down, wants to keep strength

    static let cutKeepStrength = CoachEvalScenario(
        id: "cut-keep-strength", title: "Cutting, bodyweight down 4 kg, keep strength",
        prompt: "I'm cutting and I've lost about 4 kg so far. "
            + "How do I keep my strength while I keep losing weight?",
        goal: .strength, experience: .intermediate, weeklyGoal: 4, sessionsPerWeek: 4,
        // A question, not a request: "keep doing what you're doing" is a legitimate answer when
        // adherence is perfect and the lifts are holding, so a card is welcome but not required.
        volumeExpectation: .atMostRecent, expectsProposal: false,
        evidenceKeywords: [
            ["bodyweight", "body weight", "4 kg", "lost", "cut", "deficit", "86", "90"],
            ["strength", "intensity", "heavy", "top set"]
        ]
    ) { builder in
        builder.profile(name: "Commercial gym", equipment: Lift.gymEquipment)
        for week in 0..<8 {
            builder.bodyweight(kg: 86 + Double(week) * 0.55, daysAgo: Double(week) * 7 + 0.5)
        }
        try builder.weeks(
            8, dayShifts: [1, 2, 4, 5], titles: ["Upper", "Lower"], saveRoutines: true
        ) { week, day in
            // Progress in the first five weeks, flat since the cut bit.
            let frozen = max(week, 3)
            let hard: Double = week >= 3 ? 8 : 9
            return day.isMultiple(of: 2)
                ? [
                    sets(Lift.bench, 4, up(90, 1.25, frozen, of: 8), 5, rpe: hard),
                    sets(Lift.row, 4, up(80, 1.25, frozen, of: 8), 6),
                    sets(Lift.press, 3, up(55, 1.25, frozen, of: 8), 5),
                    sets(Lift.pulldown, 3, 70, 10)
                ]
                : [
                    sets(Lift.squat, 4, up(130, 2.5, frozen, of: 8), 5, rpe: hard),
                    sets(Lift.deadlift, 2, up(160, 2.5, frozen, of: 8), 5),
                    sets(Lift.legPress, 3, 220, 10),
                    sets(Lift.legCurl, 3, 55, 12)
                ]
        }
    }

    // MARK: - 7. Squat-focused: how long to 140 kg

    static let squatForecast = CoachEvalScenario(
        id: "squat-forecast", title: "Squat-focused, asks how long to 140 kg",
        prompt: "How long until I can squat 140 kg for a single?",
        goal: .strength, experience: .intermediate, weeklyGoal: 3, sessionsPerWeek: 3,
        volumeExpectation: .any, expectsProposal: false,
        evidenceKeywords: [
            ["week", "month"], ["140"], ["117", "120", "current", "recent", "e1rm", "estimated"]
        ]
    ) { builder in
        builder.profile(name: "Commercial gym", equipment: Lift.gymEquipment)
        builder.bodyweight(kg: 80, daysAgo: 1)
        try builder.weeks(
            8, dayShifts: [1, 3, 5], titles: ["Squat A", "Squat B", "Squat C"], saveRoutines: true
        ) { week, day in
            let squatKg = up(100, 2.5, week, of: 8)
            let second = day == 2
                ? sets(Lift.deadlift, 3, up(130, 2.5, week, of: 8), 5)
                : sets(Lift.bench, 3, up(75, 1.25, week, of: 8), 5)
            return [
                day == 1 ? sets(Lift.squat, 5, squatKg, 3) : sets(Lift.squat, 3, squatKg, 5),
                second,
                sets(Lift.row, 3, 70, 8, rpe: 7)
            ]
        }
    }

    // MARK: - 8. "make me a routine"

    static let ambiguousRoutine = CoachEvalScenario(
        id: "ambiguous-routine", title: "\"make me a routine\" (ambiguous)",
        prompt: "make me a routine",
        goal: .hypertrophy, experience: nil, weeklyGoal: 3, sessionsPerWeek: 1,
        volumeExpectation: .any,
        evidenceKeywords: [["assum", "going with", "i'll take", "based on your"], ["three", "3"]]
    ) { builder in
        builder.profile(name: "Commercial gym", equipment: Lift.gymEquipment)
        builder.bodyweight(kg: 77, daysAgo: 2)
        try builder.weeks(
            5, dayShifts: [1, 3, 5], titles: ["Push", "Pull", "Legs"], saveRoutines: true
        ) { week, day in
            switch day {
            case 0:
                [
                    sets(Lift.bench, 3, up(60, 2.5, week, of: 5), 8),
                    sets(Lift.press, 3, up(35, 1.25, week, of: 5), 8),
                    sets(Lift.pushdown, 3, 25, 12),
                    sets(Lift.lateralRaise, 3, 8, 15)
                ]
            case 1:
                [
                    sets(Lift.pulldown, 3, up(55, 2.5, week, of: 5), 10),
                    sets(Lift.row, 3, up(55, 2.5, week, of: 5), 8),
                    sets(Lift.curl, 3, 25, 10)
                ]
            default:
                [
                    sets(Lift.squat, 3, up(80, 2.5, week, of: 5), 8),
                    sets(Lift.rdl, 3, up(70, 2.5, week, of: 5), 10),
                    sets(Lift.legPress, 3, 140, 12)
                ]
            }
        }
    }
}
