import Foundation

/// One entry point for the rule-based coach: ten deterministic rules over training history,
/// producing cards the lifter can approve or dismiss. No AI, no model, no network — every
/// threshold lives in `TrainingConstants`, and every rule reuses an existing GymCore engine
/// rather than re-deriving its own signal (see `Coach/CoachRules+*.swift`).
///
/// Pure function: same `input`/`now`/`calendar` in, same cards out. `now` and `calendar` are
/// passed in rather than read internally, like every other GymCore engine.
public enum CoachEngine {
    /// Every rule's cards, minus anything a higher-priority card already explains, minus anything
    /// still in cooldown from a past dismissal or approval, sorted most-important-first and capped
    /// to `TrainingConstants.coachMaxCards` — a brand-new lifter with three workouts should see at
    /// most a handful of cards, not one per rule.
    ///
    /// Rules run in an order that matters, because several of them see the same event from
    /// different angles:
    ///  * `stalledLift` runs first and claims its lift; `e1rmDowntrend` and `deloadOverdue` then
    ///    stay quiet about that lift. One lift that has stopped moving is one problem.
    ///  * `returnFromLayoff` claims "you didn't train": `adherenceDrop` and `muscleCoverageGap`
    ///    are exactly the same fact, restated as a completion rate and as a set count.
    public static func cards(for input: CoachInput, now: Date, calendar: Calendar) -> [CoachCard] {
        var cards: [CoachCard] = []

        var coveredLifts: Set<String> = []
        if let stalled = CoachRules.stalledLift(input: input) { coveredLifts.insert(stalled.name) }
        cards += CoachRules.stalledLiftCards(input: input, now: now)
        cards += CoachRules.e1rmDowntrendCards(input: input, now: now, coveredLifts: coveredLifts)
        cards += CoachRules.deloadOverdueCards(input: input, now: now, coveredLifts: coveredLifts)

        let layoff = CoachRules.returnFromLayoffCards(input: input, now: now)
        cards += layoff
        if layoff.isEmpty {
            cards += CoachRules.adherenceDropCards(input: input, now: now, calendar: calendar)
            cards += CoachRules.muscleCoverageCards(input: input, now: now)
        }

        cards += CoachRules.sessionDriftCards(input: input, now: now, calendar: calendar)
        cards += CoachRules.strugglingExerciseCards(input: input, now: now)
        cards += CoachRules.recoveryDebtCards(input: input, now: now)
        cards += CoachRules.prMilestoneCards(input: input, now: now)

        let active = cards.filter { !isSuppressed($0, interactions: input.interactions, now: now) }
        return Array(active.sorted(by: >).prefix(TrainingConstants.coachMaxCards))
    }

    /// The deload-overdue card on its own, before collapsing and before the `coachMaxCards` cap —
    /// so the Home screen's "Why a deload?" card and the Coach tab show the *same* suggestion,
    /// with the same wording, the same lift names and the same fingerprint. Still nil when no
    /// deload is warranted; callers apply `isSuppressed` themselves.
    public static func deloadCard(for input: CoachInput, now: Date) -> CoachCard? {
        CoachRules.deloadOverdueCards(input: input, now: now, coveredLifts: []).first
    }

    /// A card is suppressed when the *same* evidence (same rule + fingerprint) was dismissed or
    /// approved within that rule's cooldown window — new evidence (a different lift, a different
    /// week) always gets through even if the rule fired recently for something else.
    public static func isSuppressed(
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
