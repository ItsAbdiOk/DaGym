import GymCore

/// The questions the app writes into the coach's composer on the lifter's behalf — from the
/// Progress hub's coverage callout, an Insights card with nothing to apply, and the muscle
/// map's least-worked rows. Each one restates the finding and ends with the ask, so the
/// thread opens on a sentence the lifter could have typed. Pure, so a test can pin every line.
enum CoachChatQuestion {
    /// "Biceps have had 4 sets in 14 days. What should I add?"
    static func coverage(finding: String) -> String {
        "\(finding). What should I add?"
    }

    /// "Chest hasn't been trained since 3 weeks ago. What should I add?" — `since` as the
    /// Balance list prints it.
    static func idle(muscle: Muscle, since: String) -> String {
        let verb = muscle.isPlural ? "haven't" : "hasn't"
        return "\(muscle.displayName) \(verb) been trained since \(since). What should I add?"
    }

    /// "Biceps have had the fewest sets this week. What should I add?"
    static func fewestSets(muscle: Muscle, inPhrase: String) -> String {
        let verb = muscle.isPlural ? "have" : "has"
        return "\(muscle.displayName) \(verb) had the fewest sets \(inPhrase). What should I add?"
    }

    /// The card's claim followed by the ask that fits its rule, for the three rules whose card
    /// has no action of its own; nil for every other rule, whose card says "Got it".
    static func forCard(_ card: CoachCard) -> String? {
        guard let ask = ask(for: card.rule) else { return nil }
        return "\(card.body) \(ask)"
    }

    private static func ask(for rule: CoachRule) -> String? {
        switch rule {
        case .muscleCoverageGap: "What should I add?"
        case .stalledLift: "How do I get it moving again?"
        case .e1rmDowntrend: "What should I change?"
        default: nil
        }
    }
}
