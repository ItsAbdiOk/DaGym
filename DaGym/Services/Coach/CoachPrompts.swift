import Foundation
import GymCore

/// Every instruction and prompt the on-device coach uses, in one place.
///
/// **Token budget.** Apple's on-device model has a 4 096-token context shared by instructions,
/// prompt, tool traffic and the reply. Each feature's prompt is kept to roughly 300–600 tokens:
/// a dozen fact lines, a candidate list capped by the caller (`ProgramExercisePool` at six per
/// muscle/mechanic, `Substitutions.candidates` at three, `TrainingDigest.pool` at a handful),
/// and never a set log. The instructions below are about 120 tokens each. The program draft is
/// the largest (pool of ~40 lines ≈ 700 tokens) and still leaves the reply plenty of room.
enum CoachPrompts {
    static let debriefInstructions = """
        You are a plain-spoken strength coach writing a short debrief of one gym session. You are \
        given numbered facts. Judge the session on those facts only. Score it 1 to 10. Write at \
        most three short bullets each for what went well, what to watch, and what to try next. \
        Every bullet must cite the ids of the facts it rests on. Do not repeat the numbers; \
        interpret them. Never mention anything the facts do not say. No greetings, no emoji.
        """

    static let substitutionInstructions = """
        You are a strength coach helping a lifter swap an exercise mid-workout. You are given the \
        exercise, the lifter's reason in their own words, the muscles that are already tired, and a \
        short numbered list of allowed replacements. Order the allowed replacements best first for \
        this reason and give each a one-line why. Only use indexes from the list. No greetings.
        """

    static let programInstructions = """
        You are a strength coach filling in a training program. The split, days, sets and reps are \
        fixed. Each slot names a muscle and whether a compound or isolation move is wanted. Pick one \
        exercise per slot from the numbered pool only, choosing exercises whose main muscle matches \
        the slot, favouring compounds for compound slots, and not repeating an exercise within a \
        day. Then give the program a short name (under 40 characters). No greetings.
        """

    static let reviewInstructions = """
        You are a strength coach reviewing four weeks of training. You are given numbered facts and \
        a small numbered pool of exercises that may be added. Propose up to three changes. Each \
        change must be one of: deload a lift, add an exercise from the pool, swap a lift for a pool \
        exercise, change a lift's rep range, change a lift's progression rule, or move a rest day. \
        Each change must cite the fact ids that justify it in one sentence. Propose nothing when the \
        facts do not call for a change. No greetings.
        """

    static let answerInstructions = """
        You are a strength coach answering one question about a lifter's own training. You cannot \
        see their history directly: call the tools to look numbers up, then answer in one or two \
        sentences. Use only numbers that a tool returned, exactly as returned, and never estimate \
        or calculate new ones. If the tools return nothing useful, say so plainly. No greetings.
        """

    static func debriefPrompt(facts: SessionSummaryFacts) -> String {
        """
        Session: \(facts.title)
        Facts:
        \(facts.facts.map(\.promptLine).joined(separator: "\n"))
        """
    }

    static func substitutionPrompt(
        exercise: SubstitutionCandidate, reason: String, candidates: [ScoredSubstitute],
        recoveryMap: [Muscle: Double]
    ) -> String {
        let tired = recoveryMap.filter { $0.value > 0.6 }.keys.map(\.displayName).sorted()
        let list = candidates.enumerated().map { index, item in
            let muscles = item.candidate.primary.map(\.displayName).joined(separator: "/")
            return "\(index + 1): \(item.candidate.name) (\(item.candidate.equipment), \(muscles))"
        }
        return """
        Swapping: \(exercise.name) (\(exercise.equipment), \
        \(exercise.primary.map(\.displayName).joined(separator: "/")))
        Reason: \(reason.isEmpty ? "not given" : reason)
        Tired muscles: \(tired.isEmpty ? "none" : tired.joined(separator: ", "))
        Allowed replacements:
        \(list.joined(separator: "\n"))
        """
    }

    static func programPrompt(
        template: ProgramTemplate, pool: [SubstitutionCandidate], request: ProgramRequest
    ) -> String {
        let slots = template.days.map { day in
            let lines = day.slots.map { slot in
                "  \(slot.id): \(slot.muscle.displayName), \(slot.mechanic), "
                    + "\(slot.sets)×\(slot.repLow)–\(slot.repHigh)"
            }
            return "\(day.name):\n" + lines.joined(separator: "\n")
        }
        let poolLines = pool.enumerated().map { index, item in
            let primary = item.primary.map(\.displayName).joined(separator: "/")
            return "\(index + 1): \(item.name) (\(item.equipment), \(primary), \(item.mechanic))"
        }
        return """
        Goal: \(request.goal.displayName), \(request.experience.displayName), \
        \(request.daysPerWeek) days a week, \(request.sessionMinutes) min sessions
        Split: \(template.splitName)
        Slots:
        \(slots.joined(separator: "\n"))
        Pool:
        \(poolLines.joined(separator: "\n"))
        """
    }

    static func reviewPrompt(digest: TrainingDigest) -> String {
        let lifts = digest.lifts.enumerated().map { "L\($0 + 1): \($1.name)" }
        let pool = digest.pool.enumerated().map { index, item in
            let primary = item.primary.map(\.displayName).joined(separator: "/")
            return "P\(index + 1): \(item.name) (\(primary))"
        }
        let days = digest.trainingDays.map(\.displayName).joined(separator: ", ")
        return """
        Facts:
        \(digest.facts.map(\.promptLine).joined(separator: "\n"))
        Lifts in the programme:
        \(lifts.joined(separator: "\n"))
        Pool of exercises that may be added:
        \(pool.isEmpty ? "(none)" : pool.joined(separator: "\n"))
        Training days: \(days.isEmpty ? "none set" : days)
        """
    }
}
