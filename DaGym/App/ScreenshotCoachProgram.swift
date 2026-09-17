import Foundation
import GymCore

/// The `coachProgram` screenshot: the lifter asks for a split, the coach answers in three
/// sentences and a four-routine program card — the card's grouped-by-routine details are the
/// shot. Names are the seed library's exact spellings, like `ScreenshotCoachChat`.
enum ScreenshotCoachProgram {
    static let question = "Can you give me a workout split that focuses on chest and shoulders?"

    static func thread(now: Date) -> CoachChatThread {
        let clock = ScreenshotCoachChat.Clock(start: now.addingTimeInterval(-5 * 60))
        var messages: [CoachChatMessage] = [.user(question, at: clock.next())]
        var volume = CoachChatMessage.tool(CoachChatToolName.getMuscleVolume.rawValue, at: clock.next())
        volume.text += " · 4 weeks"
        var recovery = CoachChatMessage.tool(CoachChatToolName.getRecovery.rawValue, at: clock.next())
        recovery.text += " · today"
        var chip = CoachChatMessage.tool(CoachChatToolName.proposeProgram.rawValue, at: clock.next())
        chip.text += " · \(program.name)"
        messages += [
            volume, recovery,
            .assistant(reply, at: clock.next()),
            chip,
            .draft(index: 0, summary: program.summary, at: clock.next())
        ]
        return ScreenshotCoachChat.thread(
            messages: messages, drafts: [.program(program)], origins: [.drafter], reviews: [], now: now
        )
    }

    static let reply = """
        Chest and delts get **two exposures a week** each; legs and back drop to maintenance so \
        you recover between them. Starting weights sit 5–10% under your last four weeks. Check \
        the card and tell me what to swap.
        """

    static let program = ProgramProposal(
        name: "Chest & Shoulder Focus", goal: .hypertrophy, daysPerWeek: 4, sessionMinutes: 60,
        routines: [
            RoutineProposal(name: "Chest & Side Delts", exercises: [
                spec(
                    "Barbell Bench Press - Medium Grip", 4, reps: 6, kg: 90,
                    reason: "Your strongest press; heavy first."
                ),
                spec(
                    "Incline Dumbbell Press", 3, reps: 10, kg: 30,
                    reason: "Upper chest, the part flat bench misses."
                ),
                spec(
                    "Side Lateral Raise", 4, reps: 15, kg: 10,
                    reason: "Side delts only grow from direct work."
                ),
                spec(
                    "Triceps Pushdown", 3, reps: 12, kg: 30,
                    reason: "Lockout help for every press."
                )
            ]),
            RoutineProposal(name: "Legs (Maintenance)", exercises: [
                spec(
                    "Barbell Squat", 3, reps: 5, kg: 130,
                    reason: "Three sets keeps the number, costs little."
                ),
                spec(
                    "Leg Press", 3, reps: 10, kg: 200,
                    reason: "Quad volume without the back fatigue."
                ),
                spec(
                    "Lying Leg Curls", 3, reps: 12, kg: 45,
                    reason: "Hamstrings get nothing from pressing."
                )
            ]),
            RoutineProposal(name: "Back & Rear Delts", exercises: [
                spec(
                    "Barbell Deadlift", 2, reps: 3, kg: 150,
                    reason: "Two heavy sets to hold the pull."
                ),
                spec(
                    "Bent Over Barbell Row", 3, reps: 8, kg: 75,
                    reason: "Balances four pressing days."
                ),
                spec(
                    "Wide-Grip Lat Pulldown", 3, reps: 10, kg: 60,
                    reason: "Lats, without loading the low back."
                ),
                spec(
                    "Face Pull", 3, reps: 15, kg: 20,
                    reason: "Rear delts keep your shoulders healthy."
                )
            ]),
            RoutineProposal(name: "Shoulders & Chest", exercises: [
                spec(
                    "Standing Military Press", 4, reps: 5, kg: 60,
                    reason: "Your heavy overhead day."
                ),
                spec(
                    "Dumbbell Bench Press", 3, reps: 10, kg: 32,
                    reason: "Second chest exposure, lighter."
                ),
                spec(
                    "Side Lateral Raise (Cable)", 3, reps: 15, kg: 7.5,
                    reason: "Constant tension at the top."
                ),
                spec(
                    "Dumbbell Shoulder Press", 3, reps: 10, kg: 24,
                    reason: "Volume after the barbell."
                )
            ])
        ]
    )

    private static func spec(
        _ name: String, _ count: Int, reps: Int, kg: Double, reason: String
    ) -> CoachChatExerciseSpec {
        CoachChatExerciseSpec(
            exerciseName: name, sets: ScreenshotCoachChat.sets(count, reps: reps, kg: kg, rpe: 8),
            restSeconds: reps <= 6 ? 180 : 90, reason: reason
        )
    }
}
