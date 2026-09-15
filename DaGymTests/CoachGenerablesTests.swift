import Foundation
import GymCore
import Testing

@testable import DaGym

#if canImport(FoundationModels)
/// The model answers with 1-based list numbers; these prove each conversion maps them onto the
/// ids the prompt showed and drops anything that points outside the list.
@Suite("Coach generables → GymCore shapes")
struct CoachGenerablesTests {
    private static let benchID = UUID()
    private static let squatID = UUID()
    private static let dumbbellPressID = UUID()
    private static let legPressID = UUID()

    private static var digest: TrainingDigest {
        TrainingDigest(
            weeks: 4,
            lifts: [
                LiftDigest(id: benchID, name: "Bench Press", sessions: 4, incrementKg: 2.5),
                LiftDigest(id: squatID, name: "Squat", sessions: 4, incrementKg: 5)
            ],
            trainingDays: [.monday, .wednesday],
            pool: [
                SubstitutionCandidate(
                    id: dumbbellPressID, name: "Dumbbell Press", primary: [.chest], equipment: "dumbbell",
                    mechanic: "compound"
                ),
                SubstitutionCandidate(
                    id: legPressID, name: "Leg Press", primary: [.quads], equipment: "machine",
                    mechanic: "compound"
                )
            ]
        )
    }

    private static func change(
        _ kind: GeneratedChangeKind, lift: Int = 0, pool: Int = 0, repLow: Int = 0, repHigh: Int = 0,
        rule: GeneratedProgressionKind? = nil, from: Int = 0, to: Int = 0
    ) -> GeneratedChange {
        GeneratedChange(
            kind: kind, lift: lift, pool: pool, repLow: repLow, repHigh: repHigh, progressionRule: rule,
            fromWeekday: from, toWeekday: to, evidence: "Because.", citedFactIDs: ["lift1"]
        )
    }

    @Test("a debrief's claims carry their text and citations through unchanged")
    func debriefConversion() {
        let generated = GeneratedDebrief(
            score: 7,
            wentWell: [GeneratedClaim(text: "Bench moved well", citedFactIDs: ["lift1"])],
            watch: [],
            tryNext: [GeneratedClaim(text: "Add a set", citedFactIDs: ["lift1", "adherence"])]
        )
        let debrief = generated.debrief
        #expect(debrief.score == 7)
        #expect(debrief.wentWell == [CoachClaim(text: "Bench moved well", citedFactIDs: ["lift1"])])
        #expect(debrief.watch.isEmpty)
        #expect(debrief.tryNext.first?.citedFactIDs == ["lift1", "adherence"])
    }

    @Test("a ranking maps 1-based picks onto candidate ids and drops out-of-range numbers")
    func rankingMapsIndexes() {
        let candidates = [
            ScoredSubstitute(candidate: Self.digest.pool[0], score: 12, reason: "Same muscles"),
            ScoredSubstitute(candidate: Self.digest.pool[1], score: 10, reason: "Same muscles")
        ]
        let generated = GeneratedRanking(picks: [
            GeneratedRankedPick(index: 2, why: "Quads"),
            GeneratedRankedPick(index: 3, why: "Not in the list"),
            GeneratedRankedPick(index: 0, why: "Zero is not a list number"),
            GeneratedRankedPick(index: 1, why: "Chest")
        ])
        let ranked: [RankedSubstitute] = generated.ranked(candidates: candidates)
        #expect(ranked.map(\.candidateID) == [Self.legPressID, Self.dumbbellPressID])
        #expect(ranked.map(\.why) == ["Quads", "Chest"])
    }

    @Test("a program draft keeps the slot id and resolves the pool number; a bad number loses its slot")
    func programDraftMapsPool() {
        let generated = GeneratedProgram(name: "Upper/Lower", picks: [
            GeneratedSlotPick(slotID: "d1s1", poolIndex: 1),
            GeneratedSlotPick(slotID: "d1s2", poolIndex: 9),
            GeneratedSlotPick(slotID: "d2s1", poolIndex: 2)
        ])
        let draft = generated.draft(pool: Self.digest.pool)
        #expect(draft.name == "Upper/Lower")
        #expect(draft.picks == [
            ProgramPick(slotID: "d1s1", exerciseID: Self.dumbbellPressID),
            ProgramPick(slotID: "d2s1", exerciseID: Self.legPressID)
        ])
    }

    @Test("deload and add resolve their lift or pool number; a zero yields no proposal")
    func deloadAndAdd() {
        let deload = Self.change(.deloadLift, lift: 2).proposal(digest: Self.digest)
        #expect(deload?.change == .deloadLift(Self.squatID))
        #expect(Self.change(.deloadLift, lift: 0).proposal(digest: Self.digest) == nil)
        #expect(Self.change(.addExercise, pool: 2).proposal(digest: Self.digest)?.change
            == .addExercise(Self.legPressID))
        #expect(Self.change(.addExercise, pool: 3).proposal(digest: Self.digest) == nil)
    }

    @Test("a swap needs both a lift and a pool number")
    func swapNeedsBothEnds() {
        let swap = Self.change(.swapExercise, lift: 1, pool: 2).proposal(digest: Self.digest)
        #expect(swap?.change == .swapExercise(from: Self.benchID, to: Self.legPressID))
        #expect(Self.change(.swapExercise, lift: 1, pool: 0).proposal(digest: Self.digest) == nil)
        #expect(Self.change(.swapExercise, lift: 0, pool: 2).proposal(digest: Self.digest) == nil)
    }

    @Test("a rep-range change carries the low and high the model gave")
    func repRange() {
        let proposal = Self.change(.changeRepRange, lift: 2, repLow: 5, repHigh: 8)
            .proposal(digest: Self.digest)
        #expect(proposal?.change == .changeRepRange(exerciseID: Self.squatID, low: 5, high: 8))
        #expect(proposal?.claim == CoachClaim(text: "Because.", citedFactIDs: ["lift1"]))
    }

    @Test("double progression without a rep range defaults to 8–12 on the lift's own increment")
    func doubleProgressionDefaults() {
        let proposal = Self.change(.changeProgressionRule, lift: 2, rule: .doubleProgression)
            .proposal(digest: Self.digest)
        let defaulted = ProgressionRule.doubleProgression(low: 8, high: 12, incrementKg: 5)
        #expect(proposal?.change == .changeProgressionRule(exerciseID: Self.squatID, rule: defaulted))
        let explicit = Self.change(
            .changeProgressionRule, lift: 1, repLow: 6, repHigh: 10, rule: .doubleProgression
        ).proposal(digest: Self.digest)
        let given = ProgressionRule.doubleProgression(low: 6, high: 10, incrementKg: 2.5)
        #expect(explicit?.change == .changeProgressionRule(exerciseID: Self.benchID, rule: given))
    }

    @Test("a missing progression kind reads as linear, and a bad lift number yields nothing")
    func linearFallback() {
        let proposal = Self.change(.changeProgressionRule, lift: 1, rule: nil).proposal(digest: Self.digest)
        let linear = ProgressionRule.linear(incrementKg: 2.5)
        #expect(proposal?.change == .changeProgressionRule(exerciseID: Self.benchID, rule: linear))
        let noSuchLift = Self.change(.changeProgressionRule, lift: 3, rule: .linear)
        #expect(noSuchLift.proposal(digest: Self.digest) == nil)
    }

    @Test("moving a rest day needs two real weekdays")
    func moveRestDay() {
        let moved = Self.change(.moveRestDay, from: 2, to: 6).proposal(digest: Self.digest)
        #expect(moved?.change == .moveRestDay(from: .monday, to: .friday))
        #expect(Self.change(.moveRestDay, from: 0, to: 6).proposal(digest: Self.digest) == nil)
        #expect(Self.change(.moveRestDay, from: 2, to: 8).proposal(digest: Self.digest) == nil)
    }
}
#endif
