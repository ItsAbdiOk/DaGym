import Foundation
import GymCore

#if canImport(FoundationModels)
import FoundationModels

/// Collects every tool result a question's session produced, so `CoachAnswerValidator` can check
/// the answer's numbers against exactly what the store said. An actor because tools run off the
/// main actor and the session may call several before answering.
actor CoachToolLog {
    private(set) var results: [CoachToolResult] = []

    func record(_ result: CoachToolResult) {
        results.append(result)
    }
}

/// One `FoundationModels.Tool` per `CoachToolQuery` case. Each is a thin shim: parse the model's
/// arguments, hop to the main actor for the store's answer, log it, hand the text back. The
/// model never sees anything the tool didn't say.
struct LastSessionsTool: Tool {
    let name = "lastSessions"
    let description = "The lifter's most recent logged sessions of one exercise: date, weight and reps."
    let answerer: any CoachToolAnswering
    let log: CoachToolLog

    @Generable
    struct Arguments {
        @Guide(description: "The exercise name, e.g. Bench Press")
        var exercise: String
    }

    func call(arguments: Arguments) async throws -> String {
        await CoachToolCall.run(.lastSessions(exercise: arguments.exercise), answerer: answerer, log: log)
    }
}

struct WeeklyVolumeTool: Tool {
    let name = "weeklyVolume"
    let description = "Working sets per week for one muscle over the last few weeks."
    let answerer: any CoachToolAnswering
    let log: CoachToolLog

    @Generable
    struct Arguments {
        @Guide(description: "The muscle, e.g. Chest, Lats, Quads")
        var muscle: String
        @Guide(description: "How many weeks back to look", .range(1...12))
        var weeks: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await CoachToolCall.run(
            .weeklyVolume(muscle: arguments.muscle, weeks: arguments.weeks), answerer: answerer, log: log
        )
    }
}

struct PersonalRecordsTool: Tool {
    let name = "personalRecords"
    let description = "The lifter's personal records on one exercise."
    let answerer: any CoachToolAnswering
    let log: CoachToolLog

    @Generable
    struct Arguments {
        @Guide(description: "The exercise name, e.g. Squat")
        var exercise: String
    }

    func call(arguments: Arguments) async throws -> String {
        await CoachToolCall.run(.personalRecords(exercise: arguments.exercise), answerer: answerer, log: log)
    }
}

struct AdherenceTool: Tool {
    let name = "adherence"
    let description = "How many planned sessions the lifter kept over the last few weeks."
    let answerer: any CoachToolAnswering
    let log: CoachToolLog

    @Generable
    struct Arguments {
        @Guide(description: "How many weeks back to look", .range(1...12))
        var weeks: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await CoachToolCall.run(.adherence(weeks: arguments.weeks), answerer: answerer, log: log)
    }
}

struct RecoveryTool: Tool {
    let name = "recovery"
    let description = "How recovered one muscle is right now, and when it was last trained."
    let answerer: any CoachToolAnswering
    let log: CoachToolLog

    @Generable
    struct Arguments {
        @Guide(description: "The muscle, e.g. Hamstrings")
        var muscle: String
    }

    func call(arguments: Arguments) async throws -> String {
        await CoachToolCall.run(.recovery(muscle: arguments.muscle), answerer: answerer, log: log)
    }
}

enum CoachToolCall {
    static func run(
        _ query: CoachToolQuery,
        answerer: any CoachToolAnswering,
        log: CoachToolLog
    ) async -> String {
        let result = await answerer.answerCoachQuery(query)
        await log.record(result)
        return result.text
    }

    static func tools(answerer: any CoachToolAnswering, log: CoachToolLog) -> [any Tool] {
        [
            LastSessionsTool(answerer: answerer, log: log),
            WeeklyVolumeTool(answerer: answerer, log: log),
            PersonalRecordsTool(answerer: answerer, log: log),
            AdherenceTool(answerer: answerer, log: log),
            RecoveryTool(answerer: answerer, log: log)
        ]
    }
}
#endif
