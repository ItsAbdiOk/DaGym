import Foundation
import GymCore

@testable import DaGym

/// A scripted `CoachLanguageModel` for tests: each method returns what the test put in (after
/// the same validators the real models apply), or throws when told to, so the fallbacks can
/// be exercised without a language model.
final class MockCoachModel: CoachLanguageModel, @unchecked Sendable {
    var availability: CoachModelAvailability = .available
    var shouldFail = false
    var debriefToReturn: SessionDebrief?
    var rankingToReturn: [RankedSubstitute] = []
    var draftToReturn: ProgramDraft?
    var proposalsToReturn: [ReviewProposal] = []
    var answerToReturn: CoachAnswer?
    private(set) var questionsAsked: [String] = []

    func debrief(facts: SessionSummaryFacts) -> AsyncThrowingStream<SessionDebrief, Error> {
        AsyncThrowingStream { continuation in
            if shouldFail {
                continuation.finish(throwing: CoachModelError.rejected)
                return
            }
            if let debriefToReturn, let validated = DebriefValidator.validate(debriefToReturn, facts: facts) {
                continuation.yield(validated)
            }
            continuation.finish()
        }
    }

    func rankSubstitutes(
        for exercise: SubstitutionCandidate, reason: String, candidates: [ScoredSubstitute],
        recoveryMap: [Muscle: Double]
    ) async throws -> [RankedSubstitute] {
        if shouldFail { throw CoachModelError.rejected }
        let ranked = SubstitutionRankingValidator.validate(rankingToReturn, candidates: candidates)
        guard let ranked else { throw CoachModelError.rejected }
        return ranked
    }

    func draftProgram(
        template: ProgramTemplate, pool: [SubstitutionCandidate], request: ProgramRequest
    ) async throws -> ProgramDraft {
        if shouldFail { throw CoachModelError.rejected }
        guard let draftToReturn else { throw CoachModelError.rejected }
        return try ProgramDraftValidator.validate(
            draftToReturn, template: template, pool: pool, request: request
        )
    }

    func reviewTraining(digest: TrainingDigest) async throws -> [ReviewProposal] {
        if shouldFail { throw CoachModelError.rejected }
        return TrainingReviewValidator.validate(proposalsToReturn, digest: digest)
    }

    func answer(question: String, tools: any CoachToolAnswering) async throws -> CoachAnswer {
        questionsAsked.append(question)
        if shouldFail { throw CoachModelError.rejected }
        guard let answerToReturn else { throw CoachModelError.rejected }
        return answerToReturn
    }
}
