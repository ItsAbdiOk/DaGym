import Foundation
import GymCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why a model call produced nothing usable. Callers fall back to `RuleCoachModel` on any of
/// these — the lifter sees the rule result, never an error.
enum CoachModelError: Error, Equatable {
    case unavailable
    /// The validator refused what the model returned.
    case rejected
}

/// `CoachLanguageModel` on Apple's on-device Foundation Models (iOS 26+). One fresh
/// `LanguageModelSession` per call — every prompt is self-contained, and a shared transcript
/// would only spend context on the previous feature's facts. Every result goes through the
/// GymCore validator before it is returned; a rejection throws `CoachModelError.rejected`.
struct FoundationCoachModel: CoachLanguageModel {
    var availability: CoachModelAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: Self.reasonText(reason))
        }
        #else
        return .unavailable(reason: "Foundation Models isn't in this build")
        #endif
    }

    #if canImport(FoundationModels)
    static func reasonText(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "this iPhone can't run Apple Intelligence"
        case .appleIntelligenceNotEnabled: "Apple Intelligence is off in Settings"
        case .modelNotReady: "the model is still downloading"
        @unknown default: "not available on this device"
        }
    }

    private func session(instructions: String, tools: [any Tool] = []) throws -> LanguageModelSession {
        guard availability.isAvailable else { throw CoachModelError.unavailable }
        return LanguageModelSession(tools: tools, instructions: instructions)
    }
    #endif

    func debrief(facts: SessionSummaryFacts) -> AsyncThrowingStream<SessionDebrief, Error> {
        AsyncThrowingStream { continuation in
            #if canImport(FoundationModels)
            let task = Task {
                do {
                    let session = try session(instructions: CoachPrompts.debriefInstructions)
                    let stream = session.streamResponse(
                        to: CoachPrompts.debriefPrompt(facts: facts), generating: GeneratedDebrief.self
                    )
                    var last: SessionDebrief?
                    var lastRaw: GeneratedContent?
                    for try await snapshot in stream {
                        lastRaw = snapshot.rawContent
                        let provisional = snapshot.content.provisionalDebrief
                        if let shown = DebriefValidator.validate(provisional, facts: facts), shown != last {
                            last = shown
                            continuation.yield(shown)
                        }
                    }
                    // The final snapshot's raw content is the complete generation; decoding it
                    // as the full type is what makes it final (a partial has optionals).
                    guard let lastRaw, let final = try? GeneratedDebrief(lastRaw).debrief,
                          let validated = DebriefValidator.validate(final, facts: facts) else {
                        throw CoachModelError.rejected
                    }
                    if validated != last { continuation.yield(validated) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
            #else
            continuation.finish(throwing: CoachModelError.unavailable)
            #endif
        }
    }

    func rankSubstitutes(
        for exercise: SubstitutionCandidate, reason: String, candidates: [ScoredSubstitute],
        recoveryMap: [Muscle: Double]
    ) async throws -> [RankedSubstitute] {
        #if canImport(FoundationModels)
        let session = try session(instructions: CoachPrompts.substitutionInstructions)
        let prompt = CoachPrompts.substitutionPrompt(
            exercise: exercise, reason: reason, candidates: candidates, recoveryMap: recoveryMap
        )
        let response = try await session.respond(to: prompt, generating: GeneratedRanking.self)
        guard let ranked = SubstitutionRankingValidator.validate(
            response.content.ranked(candidates: candidates), candidates: candidates
        ) else { throw CoachModelError.rejected }
        return ranked
        #else
        throw CoachModelError.unavailable
        #endif
    }

    func draftProgram(
        template: ProgramTemplate, pool: [SubstitutionCandidate], request: ProgramRequest
    ) async throws -> ProgramDraft {
        #if canImport(FoundationModels)
        let session = try session(instructions: CoachPrompts.programInstructions)
        let prompt = CoachPrompts.programPrompt(template: template, pool: pool, request: request)
        let response = try await session.respond(to: prompt, generating: GeneratedProgram.self)
        do {
            return try ProgramDraftValidator.validate(
                response.content.draft(pool: pool), template: template, pool: pool, request: request
            )
        } catch {
            throw CoachModelError.rejected
        }
        #else
        throw CoachModelError.unavailable
        #endif
    }

    func reviewTraining(digest: TrainingDigest) async throws -> [ReviewProposal] {
        #if canImport(FoundationModels)
        let session = try session(instructions: CoachPrompts.reviewInstructions)
        let response = try await session.respond(
            to: CoachPrompts.reviewPrompt(digest: digest), generating: GeneratedReview.self
        )
        let proposals = response.content.changes.compactMap { $0.proposal(digest: digest) }
        return TrainingReviewValidator.validate(proposals, digest: digest)
        #else
        throw CoachModelError.unavailable
        #endif
    }

    func answer(question: String, tools: any CoachToolAnswering) async throws -> CoachAnswer {
        #if canImport(FoundationModels)
        let log = CoachToolLog()
        let toolCallTools = CoachToolCall.tools(answerer: tools, log: log)
        let session = try session(
            instructions: CoachPrompts.answerInstructions, tools: toolCallTools
        )
        let response = try await session.respond(to: question)
        let results = await log.results
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGrounded = !results.isEmpty
            && CoachAnswerValidator.isGrounded(answer: text, toolResults: results)
        return CoachAnswer(
            text: text, toolResults: results,
            isGrounded: isGrounded
        )
        #else
        throw CoachModelError.unavailable
        #endif
    }
}
