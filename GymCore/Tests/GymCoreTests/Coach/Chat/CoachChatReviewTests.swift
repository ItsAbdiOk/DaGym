import Foundation
import Testing

@testable import GymCore

@Suite("Coach chat review: the reviewer's tool set and verdict types")
struct CoachChatReviewTests {
    @Test("the reviewer gets every drafter tool plus agree_with_proposal; the drafter never sees agree")
    func reviewerTools() throws {
        let drafter = Set(CoachChatToolCatalog.tools.map(\.name))
        let reviewer = Set(CoachChatToolCatalog.reviewerTools.map(\.name))
        #expect(!drafter.contains(CoachChatToolName.agreeWithProposal.rawValue))
        #expect(reviewer == drafter.union([CoachChatToolName.agreeWithProposal.rawValue]))
        #expect(CoachChatToolCatalog.reviewerTools.count == CoachChatToolCatalog.tools.count + 1)
        #expect(CoachChatToolName.agreeWithProposal.isReviewerOnly)
        #expect(!CoachChatToolName.agreeWithProposal.isProposal)
        #expect(CoachChatToolName.agreeWithProposal.activityLabel == "Agreeing with the proposal")

        let tool = try #require(CoachChatToolCatalog.tool(named: "agree_with_proposal"))
        #expect(Set(tool.parameters.properties?.keys ?? [:].keys) == ["reasons", "confidence"])
        #expect(tool.parameters.required == ["reasons", "confidence"])
        #expect(tool.parameters.properties?["confidence"]?.enum == ["high", "medium"])
    }

    @Test("agreement arguments decode from the schema's shape and are trimmed and capped")
    func agreement() throws {
        let json = #"{"reasons":["  Volume matches last 4 weeks ","","Weights 5% under best"],"#
            + #""confidence":"high"}"#
        let decoded = try JSONDecoder().decode(CoachChatAgreement.self, from: Data(json.utf8))
        let validated = try decoded.validated().get()
        #expect(validated.reasons == ["Volume matches last 4 weeks", "Weights 5% under best"])
        #expect(validated.confidence == .high)

        let blank = CoachChatAgreement(reasons: ["  ", ""], confidence: .medium)
        #expect(throws: CoachChatDraftRejection.self) { try blank.validated().get() }

        let long = CoachChatAgreement(
            reasons: Array(repeating: String(repeating: "x", count: 300), count: 9), confidence: .medium
        )
        let capped = try long.validated().get()
        #expect(capped.reasons.count == CoachChatAgreement.reasonsRange.upperBound)
        #expect(capped.reasons.allSatisfy { $0.count == CoachChatAgreement.maxReasonLength })
    }

    @Test("a review round-trips through JSON with every verdict")
    func reviewCodable() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let reviews = [
            CoachChatReview(draftIndex: 0, reviewerModelID: "anthropic/claude-opus-5",
                            verdict: .agreed(reasons: ["Fine"], confidence: "high"), finishedAt: date),
            CoachChatReview(draftIndex: 1, reviewerModelID: "anthropic/claude-opus-5",
                            verdict: .alternative(draftIndex: 2, rationale: "Dropped a set."),
                            finishedAt: date),
            CoachChatReview(draftIndex: 3, reviewerModelID: "anthropic/claude-opus-5",
                            verdict: .failed(reason: "Timed out."), finishedAt: date)
        ]
        let data = try JSONEncoder().encode(reviews)
        #expect(try JSONDecoder().decode([CoachChatReview].self, from: data) == reviews)
        #expect(reviews[1].alternativeDraftIndex == 2)
        #expect(reviews[0].alternativeDraftIndex == nil)
    }

    @Test("a draft encodes for the reviewer as its tool name plus snake_case arguments")
    func proposalJSON() throws {
        let draft = CoachChatDraft.deload(DeloadProposal(exerciseName: "Bench Press", percent: 10))
        #expect(draft.toolName == .proposeDeload)
        let json = try draft.proposalJSON()
        #expect(json.hasPrefix(#"{"tool":"propose_deload","arguments":{"#))
        #expect(json.contains(#""exercise_name":"Bench Press""#))
        #expect(json.contains(#""percent":10"#))
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["tool"] as? String == "propose_deload")
    }
}
