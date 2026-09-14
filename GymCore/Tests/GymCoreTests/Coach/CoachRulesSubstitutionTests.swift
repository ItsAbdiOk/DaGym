import Foundation
import Testing
@testable import GymCore

@Suite("Coach: struggling exercise")
struct CoachRulesSubstitutionTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    private let bench = SubstitutionCandidate(
        id: UUID(), name: "Barbell Bench Press", primary: [.chest], secondary: [.triceps],
        equipment: "barbell", mechanic: "compound"
    )
    private let inclineDB = SubstitutionCandidate(
        id: UUID(), name: "Incline Dumbbell Press", primary: [.chest], secondary: [.triceps],
        equipment: "dumbbell", mechanic: "compound"
    )

    private func lift(failures: Int, withCandidate: Bool = true) -> CoachLiftSnapshot {
        CoachLiftSnapshot(
            name: "Barbell Bench Press", stallState: StallState(), e1rmTrend: [],
            consecutiveFailedSessions: failures, substitutionCandidate: withCandidate ? bench : nil
        )
    }

    private func input(
        failures: Int, withCandidate: Bool = true, interactions: [CoachInteraction] = []
    ) -> CoachInput {
        CoachInput(
            lifts: [lift(failures: failures, withCandidate: withCandidate)],
            substitutionLibrary: [bench, inclineDB], availableEquipment: ["dumbbell"],
            interactions: interactions
        )
    }

    @Test("2 consecutive failed/skipped sessions offers a substitution")
    func fires() {
        let cards = CoachEngine.cards(for: input(failures: 2), now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .strugglingExercise })
        let card = cards.first { $0.rule == .strugglingExercise }
        guard case .substituteExercise(_, _, let candidateName) = card?.suggestedAction else {
            Issue.record("expected a substitution suggestion")
            return
        }
        #expect(candidateName == "Incline Dumbbell Press")
    }

    @Test("1 failed session (just under the threshold) doesn't fire")
    func nearMissDoesNotFire() {
        let cards = CoachEngine.cards(for: input(failures: 1), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .strugglingExercise })
    }

    @Test("no resolved substitution candidate for the lift doesn't fire even past the threshold")
    func noCandidateDoesNotFire() {
        let noCandidateInput = input(failures: 3, withCandidate: false)
        let cards = CoachEngine.cards(for: noCandidateInput, now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .strugglingExercise })
    }

    @Test("a dismissed card stays suppressed through its cooldown")
    func dismissedStaysQuiet() {
        let fingerprint = CoachCard.makeFingerprint(rule: .strugglingExercise, key: "Barbell Bench Press")
        let interaction = CoachInteraction(
            rule: .strugglingExercise, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let cards = CoachEngine.cards(
            for: input(failures: 2, interactions: [interaction]), now: now, calendar: calendar
        )
        #expect(!cards.contains { $0.rule == .strugglingExercise })
    }
}
