import Foundation
import Testing

@testable import GymCore

@Suite("Substitution ranking: validator and reason parser")
struct SubstitutionRankingTests {
    private let ids = (0..<3).map { _ in UUID() }
    private var candidates: [ScoredSubstitute] {
        ids.enumerated().map { index, id in
            ScoredSubstitute(
                candidate: SubstitutionCandidate(
                    id: id, name: "Candidate \(index)", primary: [.chest], equipment: "dumbbell",
                    mechanic: "compound"
                ),
                score: Double(10 - index), reason: "Same chest, rule \(index)"
            )
        }
    }

    @Test("a foreign id is rejected, a duplicate collapsed, the rest appended in rule order")
    func foreignIDsRejected() throws {
        let ranked = [
            RankedSubstitute(candidateID: UUID(), why: "Made up"),
            RankedSubstitute(candidateID: ids[2], why: "Best today"),
            RankedSubstitute(candidateID: ids[2], why: "Again")
        ]
        let result = try #require(SubstitutionRankingValidator.validate(ranked, candidates: candidates))
        #expect(result.map(\.candidateID) == [ids[2], ids[0], ids[1]])
        #expect(result[0].why == "Best today")
        #expect(result[1].why == "Same chest, rule 0")
    }

    @Test("nothing valid means nil, so the caller keeps the rule order")
    func nothingValidIsNil() {
        let ranked = [RankedSubstitute(candidateID: UUID(), why: "x")]
        #expect(SubstitutionRankingValidator.validate(ranked, candidates: candidates) == nil)
        #expect(SubstitutionRankingValidator.ruleOrder(candidates).map(\.candidateID) == ids)
    }

    @Test("an empty why keeps the rule's reason")
    func emptyWhyFallsBack() throws {
        let ranked = [RankedSubstitute(candidateID: ids[1], why: "  ")]
        let result = try #require(SubstitutionRankingValidator.validate(ranked, candidates: candidates))
        #expect(result[0].why == "Same chest, rule 1")
    }

    @Test("free text maps onto the closed reason set")
    func reasonParsing() {
        #expect(SwapReasonParser.parse("the leg press machine is taken") == .machineTaken)
        #expect(SwapReasonParser.parse("no barbell free") == .noBarbell)
        #expect(SwapReasonParser.parse("my shoulder hurts") == .shoulderHurts)
        #expect(SwapReasonParser.parse("knee is a bit sore") == .painArea(.quads))
        #expect(SwapReasonParser.parse("short on time today") == .shortOnTime)
        #expect(SwapReasonParser.parse("") == nil)
        #expect(SwapReasonParser.parse("feeling great") == nil)
    }
}
