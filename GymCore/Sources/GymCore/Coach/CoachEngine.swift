import Foundation

/// One entry point for the rule-based coach: ten deterministic rules over training history,
/// producing cards the lifter can approve or dismiss. No AI, no model, no network — every
/// threshold lives in `TrainingConstants`, and every rule reuses an existing GymCore engine
/// rather than re-deriving its own signal (see `Coach/CoachRules+*.swift`).
///
/// Pure function: same `input`/`now`/`calendar` in, same cards out. `now` and `calendar` are
/// passed in rather than read internally, like every other GymCore engine.
public enum CoachEngine {
    /// Every rule's cards, minus anything still in cooldown from a past dismissal or approval,
    /// sorted most-important-first and capped to `TrainingConstants.coachMaxCards` — a brand-new
    /// lifter with three workouts should see at most a handful of cards, not one per rule.
    public static func cards(for input: CoachInput, now: Date, calendar: Calendar) -> [CoachCard] {
        var cards: [CoachCard] = []
        cards += CoachRules.adherenceDropCards(input: input, now: now, calendar: calendar)
        cards += CoachRules.sessionDriftCards(input: input, now: now)
        cards += CoachRules.muscleCoverageCards(input: input, now: now)
        cards += CoachRules.stalledLiftCards(input: input, now: now)
        cards += CoachRules.e1rmDowntrendCards(input: input, now: now)
        cards += CoachRules.deloadOverdueCards(input: input, now: now)
        cards += CoachRules.strugglingExerciseCards(input: input, now: now)
        cards += CoachRules.recoveryDebtCards(input: input, now: now)
        cards += CoachRules.prMilestoneCards(input: input, now: now)
        cards += CoachRules.returnFromLayoffCards(input: input, now: now)

        let active = cards.filter { !isSuppressed($0, interactions: input.interactions, now: now) }
        return Array(active.sorted(by: >).prefix(TrainingConstants.coachMaxCards))
    }

    /// A card is suppressed when the *same* evidence (same rule + fingerprint) was dismissed or
    /// approved within that rule's cooldown window — new evidence (a different lift, a different
    /// week) always gets through even if the rule fired recently for something else.
    private static func isSuppressed(
        _ card: CoachCard, interactions: [CoachInteraction], now: Date
    ) -> Bool {
        interactions.contains { interaction in
            guard interaction.rule == card.rule, interaction.fingerprint == card.fingerprint else {
                return false
            }
            guard interaction.date <= now else { return true }
            let elapsedDays = now.timeIntervalSince(interaction.date) / 86_400
            return elapsedDays < Double(card.rule.cooldownDays)
        }
    }
}
