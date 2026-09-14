import Foundation
import Testing
@testable import GymCore

@Suite("Coach: stalled lift")
struct CoachRulesStalledLiftTests {
    private let now = CoachTestSupport.date("2024-01-12T00:00:00Z")
    private let calendar = CoachTestSupport.calendar

    /// A barbell lift on a 2.5 kg plate grid, so the rule can name a real deload weight.
    private func lift(misses: Int, weightKg: Double = 60, grid: LoadGrid? = nil) -> CoachLiftSnapshot {
        CoachLiftSnapshot(
            name: "Bench Press", exerciseID: UUID(),
            stallState: StallState(consecutiveMisses: misses, lastWeightKg: weightKg),
            e1rmTrend: [], loadGrid: grid ?? .step(2.5),
            lastWorkingWeightKg: weightKg, lastWorkingSetCount: 4
        )
    }

    /// A persisted 1 is two logged sessions short of target — the counter lags a session (see
    /// `TrainingConstants.coachStalledLiftMisses`), and it is the last point before the linear
    /// rule deloads on its own.
    @Test("one persisted miss — two real sessions — fires")
    func fires() {
        let cards = CoachEngine.cards(for: CoachInput(lifts: [lift(misses: 1)]), now: now, calendar: calendar)
        #expect(cards.contains { $0.rule == .stalledLift })
        let card = cards.first { $0.rule == .stalledLift }
        guard case .deloadExercise(let name, _, _) = card?.suggestedAction else {
            Issue.record("expected a deload suggestion")
            return
        }
        #expect(name == "Bench Press")
    }

    @Test("a lift that isn't stalling at all doesn't fire")
    func nearMissDoesNotFire() {
        let cards = CoachEngine.cards(for: CoachInput(lifts: [lift(misses: 0)]), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .stalledLift })
    }

    @Test("the card reports sessions, not the lagging persisted counter")
    func bodyReportsRealSessions() {
        let card = CoachEngine.cards(for: CoachInput(lifts: [lift(misses: 1)]), now: now, calendar: calendar)
            .first { $0.rule == .stalledLift }
        #expect(card?.body.contains("2 sessions in a row") == true)
        #expect(card?.evidence.contains(CoachEvidenceItem("Sessions without progress", .count(2))) == true)
    }

    @Test("the suggested weight lands on the lift's own grid, never a raw 90%")
    func deloadWeightIsOnTheGrid() {
        // 82.5 × 0.9 = 74.25, which is not a weight: the 2.5 kg grid's nearest load below is 72.5.
        let input = CoachInput(lifts: [lift(misses: 1, weightKg: 82.5)])
        let cards = CoachEngine.cards(for: input, now: now, calendar: calendar)
        guard case .deloadExercise(_, _, let toWeightKg)? =
            cards.first(where: { $0.rule == .stalledLift })?.suggestedAction else {
            Issue.record("expected a deload suggestion")
            return
        }
        #expect(toWeightKg == 72.5)
        #expect(toWeightKg < 82.5)
    }

    @Test("a lift already on the lightest load is carded, but with no weight to offer")
    func lightestLoadOffersNoDeload() {
        // Nothing below one 5 kg step: 90 % of it isn't a load this equipment has.
        let input = CoachInput(lifts: [lift(misses: 4, weightKg: 5, grid: .step(5))])
        let card = CoachEngine.cards(for: input, now: now, calendar: calendar)
            .first { $0.rule == .stalledLift }
        #expect(card != nil)
        #expect(offersNoWeight(card))
        #expect(card?.body.contains("nothing lighter") == true)
    }

    @Test("bodyweight work (no grid) is carded without inventing a weight")
    func bodyweightOffersNoDeload() {
        let input = CoachInput(lifts: [CoachLiftSnapshot(
            name: "Pull-Up", stallState: StallState(consecutiveMisses: 1, lastWeightKg: 0),
            e1rmTrend: [], loadGrid: nil, lastWorkingWeightKg: 0
        )])
        let card = CoachEngine.cards(for: input, now: now, calendar: calendar)
            .first { $0.rule == .stalledLift }
        #expect(card != nil)
        #expect(offersNoWeight(card))
    }

    /// The card fired but has no concrete weight to suggest.
    private func offersNoWeight(_ card: CoachCard?) -> Bool {
        guard let card else { return false }
        if case .none = card.suggestedAction { return true }
        return false
    }

    @Test("no lifts never fires")
    func noLiftsDoesNotFire() {
        let cards = CoachEngine.cards(for: CoachInput(lifts: []), now: now, calendar: calendar)
        #expect(!cards.contains { $0.rule == .stalledLift })
    }

    @Test("a dismissed card stays suppressed through its cooldown, then comes back")
    func dismissedStaysQuietThenReturns() {
        let fingerprint = CoachCard.makeFingerprint(rule: .stalledLift, key: "Bench Press")
        let interaction = CoachInteraction(
            rule: .stalledLift, fingerprint: fingerprint, outcome: .dismissed, date: now
        )
        let input = CoachInput(lifts: [lift(misses: 1)], interactions: [interaction])
        #expect(!CoachEngine.cards(for: input, now: now, calendar: calendar)
            .contains { $0.rule == .stalledLift })

        let after = CoachTestSupport.daysFromNow(
            TrainingConstants.coachStalledLiftCooldownDays + 1, from: now
        )
        #expect(CoachEngine.cards(for: input, now: after, calendar: calendar)
            .contains { $0.rule == .stalledLift })
    }

    @Test("the fingerprint doesn't move while the same lift is stuck at the same weight")
    func fingerprintIsStableWhileTheProblemIs() {
        let today = CoachEngine.cards(for: CoachInput(lifts: [lift(misses: 1)]), now: now, calendar: calendar)
        // Tomorrow, one more miss on the same lift: the same problem, so the same key — a
        // dismissal must last its cooldown rather than being undone by the clock.
        let tomorrow = CoachTestSupport.daysFromNow(1, from: now)
        let later = CoachEngine.cards(
            for: CoachInput(lifts: [lift(misses: 2)]), now: tomorrow, calendar: calendar
        )
        #expect(today.first { $0.rule == .stalledLift }?.fingerprint
            == later.first { $0.rule == .stalledLift }?.fingerprint)
    }
}
