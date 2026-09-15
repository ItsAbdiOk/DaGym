import Foundation
import Testing

@testable import GymCore

@Suite("ExerciseHints")
struct ExerciseHintsTests {
    @Test("a name keyword is found with no category")
    func nameKeywordNoCategory() {
        #expect(ExerciseHints.primaryMuscles(name: "Kirk Shrug Machine", category: nil) == [.traps])
    }

    @Test("a FitNotes category wins over the name")
    func categoryWinsOverName() {
        let muscles = ExerciseHints.primaryMuscles(name: "Some Invented Lift", category: "Shoulders")
        #expect(muscles == [.delts])
    }

    @Test("deadlift maps to two muscles")
    func deadliftKeyword() {
        #expect(ExerciseHints.primaryMuscles(name: "Trap Bar Deadlift", category: nil) == [.lowerBack, .hams])
    }

    @Test("a name with no keyword and no category is empty")
    func noSignalIsEmpty() {
        #expect(ExerciseHints.primaryMuscles(name: "Treadmill", category: nil).isEmpty)
    }

    @Test("lateral raise is not mistaken for the row/lat keyword")
    func lateralIsNotLat() {
        #expect(ExerciseHints.primaryMuscles(name: "Lateral Raise", category: nil) == [.delts])
    }

    @Test("specific multi-word rules beat the generic single words they overlap")
    func specificRulesWinOverGenericWords() {
        let cases: [(String, [Muscle])] = [
            ("Lying Leg Curl", [.hams]),
            ("Seated Leg Curl", [.hams]),
            ("Hamstring Curl", [.hams]),
            ("Wrist Curl", [.forearms]),
            ("Reverse Wrist Curl", [.forearms]),
            ("Overhead Triceps Extension", [.triceps]),
            ("Tricep Pushdown", [.triceps]),
            ("Rear Delt Fly", [.delts]),
            ("Chest Supported Row", [.lats]),
            ("Chest-Supported Row", [.lats]),
            ("Barbell Curl", [.biceps]),
            ("Incline Bench", [.chest]),
            ("Overhead Press", [.delts])
        ]
        for (name, expected) in cases {
            #expect(ExerciseHints.primaryMuscles(name: name, category: nil) == expected, "\(name)")
        }
    }

    @Test("cardio style: distance and no reps")
    func cardioStyle() {
        let style = ExerciseHints.loggingStyle(hasReps: false, hasTime: true, hasDistance: true)
        #expect(style == .cardio)
    }

    @Test("timed-hold style: time only, no reps")
    func timedHoldStyle() {
        let style = ExerciseHints.loggingStyle(hasReps: false, hasTime: true, hasDistance: false)
        #expect(style == .timedHold)
    }

    @Test("weight x reps style: reps present")
    func weightRepsStyle() {
        let style = ExerciseHints.loggingStyle(hasReps: true, hasTime: false, hasDistance: false)
        #expect(style == .weightReps)
    }
}
