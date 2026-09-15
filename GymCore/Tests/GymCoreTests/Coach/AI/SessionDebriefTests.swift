import Foundation
import Testing

@testable import GymCore

@Suite("Session debrief: validator and rule fallback")
struct SessionDebriefTests {
    private let facts = SessionSummaryFacts(
        title: "Push A", durationMinutes: 52, volumeKg: 6_840, previousVolumeKg: 6_400, setsDone: 18,
        previousSetsDone: 18, skippedSets: 2, setsBelowLast: 1, personalRecords: ["Bench Press"],
        averageRPE: 8.4, previousAverageRPE: 7.6, e1rmUp: ["Bench Press"], e1rmDown: []
    )

    @Test("facts only list what exists, with the documented ids")
    func factsAreConditional() {
        let ids = facts.factIDs
        #expect(ids.contains(SessionSummaryFacts.FactID.volumeChange))
        #expect(ids.contains(SessionSummaryFacts.FactID.rpeDrift))
        #expect(!ids.contains(SessionSummaryFacts.FactID.e1rmDown))
        let first = SessionSummaryFacts(title: "First", durationMinutes: 40, volumeKg: 1_000, setsDone: 10)
        #expect(!first.factIDs.contains(SessionSummaryFacts.FactID.volumeChange))
        #expect(first.facts.count == 3)
    }

    @Test("a score outside 1…10 rejects the whole debrief")
    func scoreOutOfRangeRejects() {
        let claim = CoachClaim(text: "PR", citedFactIDs: [SessionSummaryFacts.FactID.prs])
        let debrief = SessionDebrief(score: 11, wentWell: [claim], watch: [], tryNext: [])
        #expect(DebriefValidator.validate(debrief, facts: facts) == nil)
        let zero = SessionDebrief(score: 0, wentWell: [claim], watch: [], tryNext: [])
        #expect(DebriefValidator.validate(zero, facts: facts) == nil)
    }

    @Test("uncited and foreign-cited bullets are dropped, cited ones kept, lists capped at three")
    func uncitedBulletsAreDropped() throws {
        let good = CoachClaim(text: "PR on bench", citedFactIDs: [SessionSummaryFacts.FactID.prs])
        let uncited = CoachClaim(text: "You looked strong", citedFactIDs: [])
        let foreign = CoachClaim(text: "Sleep was poor", citedFactIDs: ["sleep"])
        let missing = CoachClaim(text: "e1RM fell", citedFactIDs: [SessionSummaryFacts.FactID.e1rmDown])
        let debrief = SessionDebrief(
            score: 8, wentWell: [uncited, good, foreign, good, good, good], watch: [missing], tryNext: []
        )
        let validated = try #require(DebriefValidator.validate(debrief, facts: facts))
        #expect(validated.wentWell.count == 3)
        #expect(validated.wentWell.allSatisfy { $0 == good })
        #expect(validated.watch.isEmpty)
    }

    @Test("a bullet with a number the facts never stated is dropped; one that repeats a fact's number stays")
    func inventedNumbersAreDropped() throws {
        let volumeChange = SessionSummaryFacts.FactID.volumeChange
        // The fact says +7 %; the model wrote 40 %.
        let invented = CoachClaim(text: "Volume was up 40% on last time.", citedFactIDs: [volumeChange])
        let repeated = CoachClaim(text: "Volume was up 7% on last time.", citedFactIDs: [volumeChange])
        let rpe = CoachClaim(text: "RPE crept up 0.8.", citedFactIDs: [SessionSummaryFacts.FactID.rpeDrift])
        let debrief = SessionDebrief(score: 7, wentWell: [invented, repeated], watch: [rpe], tryNext: [])
        let validated = try #require(DebriefValidator.validate(debrief, facts: facts))
        #expect(validated.wentWell == [repeated])
        #expect(validated.watch == [rpe])
    }

    @Test("nothing cited at all means no debrief, not an empty card")
    func allDroppedIsNil() {
        let debrief = SessionDebrief(
            score: 5, wentWell: [CoachClaim(text: "x", citedFactIDs: [])], watch: [], tryNext: []
        )
        #expect(DebriefValidator.validate(debrief, facts: facts) == nil)
    }

    @Test("the rule debrief passes its own validator unchanged and reads the thresholds")
    func ruleDebriefIsValid() {
        let debrief = DebriefRules.debrief(from: facts)
        #expect(DebriefValidator.validate(debrief, facts: facts) == debrief)
        // +2 PR, +1 volume, −1 skipped, −1 RPE drift from a base of 6.
        #expect(debrief.score == 7)
        #expect(debrief.wentWell.contains { $0.citedFactIDs == [SessionSummaryFacts.FactID.prs] })
        #expect(debrief.watch.contains { $0.citedFactIDs == [SessionSummaryFacts.FactID.rpeDrift] })
        #expect(debrief.watch.contains { $0.citedFactIDs == [SessionSummaryFacts.FactID.skipped] })
    }

    @Test("a first, clean session still gets one bullet per list")
    func firstSessionHasSomethingToSay() {
        let first = SessionSummaryFacts(title: "Legs", durationMinutes: 45, volumeKg: 3_000, setsDone: 12)
        let debrief = DebriefRules.debrief(from: first)
        #expect(!debrief.wentWell.isEmpty)
        #expect(!debrief.tryNext.isEmpty)
        #expect(DebriefValidator.validate(debrief, facts: first) != nil)
    }
}
