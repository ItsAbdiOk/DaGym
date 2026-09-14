import Foundation

/// Recovery-debt rule: reads the `Recovery.map` output the app layer already computed (0 fresh
/// … 1 spent) — no fatigue math of its own, just a "how many muscles are over the line" count.
///
/// Descriptive, never diagnostic: the card reports how much work went into those muscles
/// recently, it does not tell the lifter what is happening inside their body.
extension CoachRules {
    static func recoveryDebtCards(input: CoachInput, now: Date) -> [CoachCard] {
        // The fatigue reference is a downward-only EWMA seeded at `recoveryFatigueScale`, so a
        // lifter's first few sessions read as an ever-larger share of a still-falling "normal".
        // Wait for enough history for the reference to mean something.
        guard input.recentSessions.count >= TrainingConstants.coachRecoveryDebtMinSessions else {
            return []
        }
        let threshold = TrainingConstants.coachRecoveryDebtThreshold
        let spent = input.recoveryMap
            .filter { $0.value >= threshold }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
            }
        guard spent.count >= TrainingConstants.coachRecoveryDebtMinMuscles else { return [] }

        let named = Array(spent.prefix(3))
        let names = named.map { $0.key.displayName }.joined(separator: ", ")
        let verb = named.count == 1 ? "has" : "have"
        let evidence = named.map { CoachEvidenceItem("\($0.key.displayName) spent score", .number($0.value)) }
        // Every muscle over the line, in a fixed order. The displayed three re-sort themselves as
        // scores decay, so keying on that ordered list changed the fingerprint overnight and a
        // dismissed card came straight back for the same muscles.
        let key = spent.map { $0.key.rawValue }.sorted().joined(separator: ",")

        return [CoachCard(
            rule: .recoveryDebt, severity: .notice, title: "You've trained these hard recently",
            body: "\(names) \(verb) taken a lot of work in the last few days — an easy day or two "
                + "would let it land.",
            evidence: evidence, suggestedAction: named.first.map { .restMuscle($0.key) } ?? .none,
            distinguishingKey: key, firedDate: now
        )]
    }
}
