import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The Coach tab's UI states, kept off the views: what Approve does when the store refuses a
/// change, what an empty model review falls back to, and how long the debrief skeleton waits.
@MainActor
@Suite("Coach section states: approve, empty review, debrief timeout")
struct CoachSectionStateTests {
    private func benchRoutine(_ store: WorkoutStore) -> (bench: ExerciseInfo, routine: RoutineInfo) {
        let bench = store.createCustomExercise(
            name: "Bench Press", primary: [.chest], equipment: "barbell", style: .weightReps
        )
        let sets = (0..<3).map { _ in PlannedSetDraft(kind: .working, targetReps: 8, targetWeightKg: 60) }
        let routine = store.saveRoutine(
            id: nil, name: "Push", rule: .linear(incrementKg: 2.5),
            exercises: [RoutineExerciseDraft(exerciseID: bench.id, sets: sets)]
        )
        return (bench, routine)
    }

    private func reviewCard(_ store: WorkoutStore, change: ReviewChange) -> CoachCard {
        let digest = store.trainingDigest()
        let proposal = ReviewProposal(change: change, claim: CoachClaim(text: "x", citedFactIDs: []))
        return ReviewCardBuilder.card(for: proposal, digest: digest, store: store, now: Date())
    }

    @Test("approving a change the store refuses records nothing and keeps the card")
    func refusedApprovalIsNotRecorded() throws {
        let store = try makeStore()
        let (bench, routine) = benchRoutine(store)
        store.saveSchedule(WeeklySchedule(days: [.monday: routine.id, .friday: routine.id]))
        // Friday is taken, so the move is refused by `applyReviewChange`.
        let change = ReviewChange.moveRestDay(from: .monday, to: .friday)
        let card = reviewCard(store, change: change)

        let outcome = ReviewApproval.approve(card: card, change: change, store: store)

        guard case .refused(let reason) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(reason.contains(card.title))
        #expect(store.coachInteractions().isEmpty)
        #expect(store.schedule().days == [.monday: routine.id, .friday: routine.id])

        // The same card with a change that takes is recorded as approved, undoably.
        let good = ReviewChange.changeRepRange(exerciseID: bench.id, low: 5, high: 8)
        guard case .applied(let applied, let interactionID) = ReviewApproval.approve(
            card: card, change: good, store: store
        ) else {
            Issue.record("expected the rep-range change to apply")
            return
        }
        #expect(applied.message.contains("5–8"))
        #expect(store.coachInteractions().map(\.outcome) == [.approved])
        store.removeCoachInteraction(id: interactionID)
        #expect(store.coachInteractions().isEmpty)
    }

    @Test("a model that validates every proposal away falls back to the rules, not to 'nothing to change'")
    func emptyModelReviewFallsBackToRules() {
        let stalled = LiftDigest(id: UUID(), name: "Bench Press", sessions: 6, isStalled: true)
        let digest = TrainingDigest(weeks: 4, lifts: [stalled])
        let fromRules = TrainingReviewRules.proposals(from: digest)
        #expect(fromRules.map(\.change) == [.deloadLift(stalled.id)])

        #expect(ReviewApproval.proposals(fromModel: [], digest: digest) == fromRules)
        #expect(ReviewApproval.proposals(fromModel: nil, digest: digest) == fromRules)
        #expect(ReviewApproval.proposals(fromModel: fromRules, digest: digest) == fromRules)
    }

    // MARK: - Debrief

    @Test("a debrief stream that never yields falls through to the rules after the timeout")
    func debriefTimesOutToRules() async {
        let facts = SessionSummaryFacts(title: "Legs", durationMinutes: 40, volumeKg: 3_000, setsDone: 12)
        let expected = DebriefValidator.validate(DebriefRules.debrief(from: facts), facts: facts)
        let silent = SilentCoachModel()

        let debrief = await DebriefLoader.load(facts: facts, model: silent, timeout: .milliseconds(50))

        #expect(debrief == expected)
        #expect(debrief != nil)
    }

    /// Collects what `DebriefLoader` hands to `onSnapshot`, on the main actor like the card.
    @MainActor
    private final class SnapshotCollector {
        var snapshots: [SessionDebrief] = []
    }

    @Test("every streamed snapshot is surfaced as it arrives, and the last one is the result")
    func intermediateSnapshotsAreSurfaced() async {
        let facts = SessionSummaryFacts(title: "Legs", durationMinutes: 40, volumeKg: 3_000, setsDone: 12)
        let partial = SessionDebrief(score: 5, wentWell: [], watch: [], tryNext: [])
        let full = SessionDebrief(score: 8, wentWell: [], watch: [], tryNext: [])
        let model = StreamingCoachModel(snapshots: [partial, full], finishes: true)
        let seen = SnapshotCollector()

        let debrief = await DebriefLoader.load(facts: facts, model: model) { seen.snapshots.append($0) }

        #expect(seen.snapshots == [partial, full])
        #expect(debrief == full)
    }

    @Test("a stream that stalls after a partial snapshot keeps that partial on timeout, not the rules")
    func timeoutKeepsLastPartial() async {
        let facts = SessionSummaryFacts(title: "Legs", durationMinutes: 40, volumeKg: 3_000, setsDone: 12)
        let partial = SessionDebrief(score: 5, wentWell: [], watch: [], tryNext: [])
        let model = StreamingCoachModel(snapshots: [partial], finishes: false)
        let seen = SnapshotCollector()

        let debrief = await DebriefLoader.load(
            facts: facts, model: model, timeout: .milliseconds(50)
        ) { seen.snapshots.append($0) }

        #expect(seen.snapshots == [partial])
        #expect(debrief == partial)
        #expect(debrief != DebriefValidator.validate(DebriefRules.debrief(from: facts), facts: facts))
    }
}

/// A model whose debrief stream yields a scripted list of snapshots and then either finishes
/// or hangs — the shape of an on-device model that streams a partial and then stalls.
private final class StreamingCoachModel: CoachLanguageModel, @unchecked Sendable {
    private let inner = MockCoachModel()
    private let snapshots: [SessionDebrief]
    private let finishes: Bool
    var availability: CoachModelAvailability { inner.availability }

    init(snapshots: [SessionDebrief], finishes: Bool) {
        self.snapshots = snapshots
        self.finishes = finishes
    }

    func debrief(facts: SessionSummaryFacts) -> AsyncThrowingStream<SessionDebrief, Error> {
        AsyncThrowingStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            if finishes { continuation.finish() }
        }
    }

    func rankSubstitutes(
        for exercise: SubstitutionCandidate, reason: String, candidates: [ScoredSubstitute],
        recoveryMap: [Muscle: Double]
    ) async throws -> [RankedSubstitute] {
        try await inner.rankSubstitutes(
            for: exercise, reason: reason, candidates: candidates, recoveryMap: recoveryMap
        )
    }

    func draftProgram(
        template: ProgramTemplate, pool: [SubstitutionCandidate], request: ProgramRequest
    ) async throws -> ProgramDraft {
        try await inner.draftProgram(template: template, pool: pool, request: request)
    }

    func reviewTraining(digest: TrainingDigest) async throws -> [ReviewProposal] {
        try await inner.reviewTraining(digest: digest)
    }

    func answer(question: String, tools: any CoachToolAnswering) async throws -> CoachAnswer {
        try await inner.answer(question: question, tools: tools)
    }
}

/// A model whose debrief stream never yields and never finishes — a warming-up or throttled
/// on-device model looks exactly like this to the caller.
private final class SilentCoachModel: CoachLanguageModel, @unchecked Sendable {
    private let inner = MockCoachModel()
    var availability: CoachModelAvailability { inner.availability }

    func debrief(facts: SessionSummaryFacts) -> AsyncThrowingStream<SessionDebrief, Error> {
        AsyncThrowingStream { _ in }
    }

    func rankSubstitutes(
        for exercise: SubstitutionCandidate, reason: String, candidates: [ScoredSubstitute],
        recoveryMap: [Muscle: Double]
    ) async throws -> [RankedSubstitute] {
        try await inner.rankSubstitutes(
            for: exercise, reason: reason, candidates: candidates, recoveryMap: recoveryMap
        )
    }

    func draftProgram(
        template: ProgramTemplate, pool: [SubstitutionCandidate], request: ProgramRequest
    ) async throws -> ProgramDraft {
        try await inner.draftProgram(template: template, pool: pool, request: request)
    }

    func reviewTraining(digest: TrainingDigest) async throws -> [ReviewProposal] {
        try await inner.reviewTraining(digest: digest)
    }

    func answer(question: String, tools: any CoachToolAnswering) async throws -> CoachAnswer {
        try await inner.answer(question: question, tools: tools)
    }
}
