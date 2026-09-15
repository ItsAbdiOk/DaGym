import Foundation
import Testing

@testable import GymCore

@Suite("Training review: validator and rule fallback")
struct TrainingReviewTests {
    private let bench = UUID()
    private let squat = UUID()
    private let poolRow = UUID()

    private var digest: TrainingDigest {
        TrainingDigest(
            weeks: 4,
            lifts: [
                LiftDigest(
                    id: bench, name: "Bench Press", e1rmChangeFraction: 0.0, sessions: 6, isStalled: true
                ),
                LiftDigest(id: squat, name: "Squat", e1rmChangeFraction: 0.05, sessions: 5)
            ],
            adherencePercent: 75, coverageGaps: [.hams], trainingDays: [.monday, .wednesday],
            pool: [SubstitutionCandidate(
                id: poolRow, name: "Leg Curl", primary: [.hams], equipment: "machine", mechanic: "isolation"
            )]
        )
    }

    private func claim(_ ids: [String]) -> CoachClaim { CoachClaim(text: "Because", citedFactIDs: ids) }

    @Test("foreign ids, uncited claims, silly rep ranges and duplicates are refused; three survive")
    func validatorRefusals() {
        let lift1 = TrainingDigest.FactID.lift(0)
        let proposals = [
            ReviewProposal(change: .deloadLift(UUID()), claim: claim([lift1])),
            ReviewProposal(change: .deloadLift(bench), claim: claim([])),
            ReviewProposal(change: .deloadLift(bench), claim: claim(["nope"])),
            ReviewProposal(change: .addExercise(UUID()), claim: claim([lift1])),
            ReviewProposal(change: .addExercise(bench), claim: claim([lift1])),
            ReviewProposal(
                change: .changeRepRange(exerciseID: squat, low: 12, high: 8), claim: claim([lift1])
            ),
            ReviewProposal(
                change: .changeRepRange(exerciseID: squat, low: 0, high: 8), claim: claim([lift1])
            ),
            ReviewProposal(change: .moveRestDay(from: .monday, to: .wednesday), claim: claim([lift1])),
            ReviewProposal(change: .swapExercise(from: poolRow, to: bench), claim: claim([lift1])),
            ReviewProposal(change: .deloadLift(bench), claim: claim([lift1])),
            ReviewProposal(change: .deloadLift(bench), claim: claim([lift1])),
            ReviewProposal(change: .addExercise(poolRow), claim: claim([TrainingDigest.FactID.gap(.hams)])),
            ReviewProposal(change: .moveRestDay(from: .monday, to: .friday), claim: claim([lift1])),
            ReviewProposal(
                change: .changeRepRange(exerciseID: squat, low: 6, high: 10), claim: claim([lift1])
            )
        ]
        let kept = TrainingReviewValidator.validate(proposals, digest: digest)
        #expect(kept.count == 3)
        #expect(kept.map(\.change) == [
            .deloadLift(bench), .addExercise(poolRow), .moveRestDay(from: .monday, to: .friday)
        ])
    }

    @Test("a claim whose number no fact, pool name or the change itself states is refused")
    func inventedNumbersAreRefused() {
        let lift2 = TrainingDigest.FactID.lift(1)
        let gap = TrainingDigest.FactID.gap(.hams)
        let proposals = [
            // The fact says e1RM +5 %; the model wrote 15 %.
            ReviewProposal(
                change: .deloadLift(squat),
                claim: CoachClaim(text: "Squat is up 15% — deload anyway.", citedFactIDs: [lift2])
            ),
            ReviewProposal(
                change: .deloadLift(squat),
                claim: CoachClaim(text: "Squat is up 5% over 5 sessions.", citedFactIDs: [lift2])
            ),
            // The proposed range is the change's own number, not an invention.
            ReviewProposal(
                change: .changeRepRange(exerciseID: squat, low: 8, high: 12),
                claim: CoachClaim(text: "Move Squat to 8–12 reps.", citedFactIDs: [lift2])
            ),
            ReviewProposal(
                change: .changeRepRange(exerciseID: bench, low: 8, high: 12),
                claim: CoachClaim(text: "Move Bench to 8–12 reps after 20 sessions.", citedFactIDs: [lift2])
            ),
            ReviewProposal(
                change: .addExercise(poolRow), claim: CoachClaim(text: "Add Leg Curl.", citedFactIDs: [gap])
            )
        ]
        let kept = TrainingReviewValidator.validate(proposals, digest: digest)
        #expect(kept.map(\.change) == [
            .deloadLift(squat), .changeRepRange(exerciseID: squat, low: 8, high: 12), .addExercise(poolRow)
        ])
        #expect(kept.first?.claim.text == "Squat is up 5% over 5 sessions.")
    }

    @Test("a non-positive progression increment is refused")
    func progressionRuleGuard() {
        let bad = ReviewProposal(
            change: .changeProgressionRule(exerciseID: bench, rule: .linear(incrementKg: 0)),
            claim: claim([TrainingDigest.FactID.lift(0)])
        )
        let good = ReviewProposal(
            change: .changeProgressionRule(exerciseID: bench, rule: .linear(incrementKg: 2.5)),
            claim: claim([TrainingDigest.FactID.lift(0)])
        )
        #expect(TrainingReviewValidator.validate([bad, good], digest: digest).map(\.change) == [good.change])
    }

    @Test("the rule review proposes a deload for the stall and an addition for the gap, both valid")
    func ruleReview() {
        let proposals = TrainingReviewRules.proposals(from: digest)
        #expect(proposals.map(\.change) == [.deloadLift(bench), .addExercise(poolRow)])
        #expect(TrainingReviewValidator.validate(proposals, digest: digest) == proposals)
    }

    @Test("the digest's facts carry the ids the rules cite")
    func digestFacts() {
        let ids = digest.factIDs
        #expect(ids.contains(TrainingDigest.FactID.adherence))
        #expect(ids.contains(TrainingDigest.FactID.gap(.hams)))
        #expect(ids.contains(TrainingDigest.FactID.lift(1)))
        let benchFact = digest.facts.first { $0.id == TrainingDigest.FactID.lift(0) }
        #expect(benchFact?.text.contains("stalled") == true)
    }
}
