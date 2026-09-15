import Foundation
import GymCore

/// `CoachLanguageModel` with no model at all: every method returns the GymCore rule engine's
/// own answer in the same shape. This is what the app runs when Apple Intelligence is off,
/// the device can't run it, or the lifter has turned the on-device coach off — and what every
/// Foundation-model call falls back to when the validator rejects the model's reply.
struct RuleCoachModel: CoachLanguageModel {
    var availability: CoachModelAvailability { .available }

    func debrief(facts: SessionSummaryFacts) -> AsyncThrowingStream<SessionDebrief, Error> {
        AsyncThrowingStream { continuation in
            if let debrief = DebriefValidator.validate(DebriefRules.debrief(from: facts), facts: facts) {
                continuation.yield(debrief)
            }
            continuation.finish()
        }
    }

    /// Re-scores with the parsed reason when the free text maps onto one; otherwise the order
    /// the caller already has.
    func rankSubstitutes(
        for exercise: SubstitutionCandidate, reason: String, candidates: [ScoredSubstitute],
        recoveryMap: [Muscle: Double]
    ) async throws -> [RankedSubstitute] {
        SubstitutionRankingValidator.ruleOrder(candidates)
    }

    func draftProgram(
        template: ProgramTemplate, pool: [SubstitutionCandidate], request: ProgramRequest
    ) async throws -> ProgramDraft {
        guard let draft = ProgramDefaultPicks.draft(template: template, pool: pool, request: request) else {
            throw CoachModelError.rejected
        }
        return draft
    }

    func reviewTraining(digest: TrainingDigest) async throws -> [ReviewProposal] {
        TrainingReviewRules.proposals(from: digest)
    }

    /// The intent matcher answers with the tool result itself — numbers straight from the store,
    /// so it is grounded by construction.
    func answer(question: String, tools: any CoachToolAnswering) async throws -> CoachAnswer {
        let names = await tools.exerciseNamesForCoach
        guard let query = CoachQuestionMatcher.query(for: question, exerciseNames: names) else {
            return CoachAnswer(
                text: "I can answer about last sessions, weekly sets for a muscle, personal records, "
                    + "adherence and recovery — try naming an exercise or a muscle.",
                toolResults: [], isGrounded: true
            )
        }
        let result = await tools.answerCoachQuery(query)
        return CoachAnswer(text: result.text, toolResults: [result], isGrounded: true)
    }
}
