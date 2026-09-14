import Foundation

/// Recovery-debt rule: reads the `Recovery.map` output the app layer already computed (0 fresh
/// … 1 spent) — no fatigue math of its own, just a "how many muscles are over the line" count.
extension CoachRules {
    static func recoveryDebtCards(input: CoachInput, now: Date) -> [CoachCard] {
        let threshold = TrainingConstants.coachRecoveryDebtThreshold
        let spent = input.recoveryMap
            .filter { $0.value >= threshold }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
            }
        guard spent.count >= TrainingConstants.coachRecoveryDebtMinMuscles else { return [] }

        let named = Array(spent.prefix(3))
        let names = named.map { $0.key.displayName }.joined(separator: ", ")
        let verb = named.count == 1 ? "is" : "are"
        let evidence = named.map { CoachEvidenceItem("\($0.key.displayName) spent score", .number($0.value)) }
        let key = named.map { $0.key.rawValue }.joined(separator: ",")

        return [CoachCard(
            rule: .recoveryDebt, severity: .notice, title: "Recovery debt is building",
            body: "\(names) \(verb) still carrying heavy fatigue — an easy day or two would help.",
            evidence: evidence, suggestedAction: named.first.map { .restMuscle($0.key) } ?? .none,
            distinguishingKey: key, firedDate: now
        )]
    }
}
