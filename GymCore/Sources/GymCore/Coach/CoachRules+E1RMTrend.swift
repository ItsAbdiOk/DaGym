import Foundation

/// e1RM-downtrend rule: its own signal, distinct from `DeloadDetector`'s 3-session regression
/// check — a longer `coachE1rmDowntrendSessions`-session window, and it only fires when every
/// step from the window's peak onward is non-increasing (one bad session isn't a trend).
extension CoachRules {
    private struct Downtrend {
        var name: String
        var peak: Double
        var last: Double
        var decline: Double
    }

    static func e1rmDowntrendCards(input: CoachInput, now: Date) -> [CoachCard] {
        let window = TrainingConstants.coachE1rmDowntrendSessions
        let fraction = TrainingConstants.coachE1rmDowntrendFraction

        let candidates = input.lifts
            .compactMap { downtrend(for: $0, window: window) }
            .filter { $0.decline >= fraction }
            .sorted { $0.decline > $1.decline }

        guard let worst = candidates.first else { return [] }
        let percent = Int((worst.decline * 100).rounded())
        let evidence: [CoachEvidenceItem] = [
            .init("Peak e1RM in window", .weightKg(worst.peak)),
            .init("Latest e1RM", .weightKg(worst.last)),
            .init("Decline", .number(worst.decline))
        ]
        return [CoachCard(
            rule: .e1rmDowntrend, severity: .warning, title: "\(worst.name)'s e1RM is trending down",
            body: "\(worst.name)'s estimated 1RM has fallen \(percent)% over its last \(window) sessions.",
            evidence: evidence, suggestedAction: .none, distinguishingKey: worst.name, firedDate: now
        )]
    }

    private static func downtrend(for lift: CoachLiftSnapshot, window: Int) -> Downtrend? {
        guard lift.e1rmTrend.count >= window else { return nil }
        let recent = Array(lift.e1rmTrend.suffix(window))
        guard let peak = recent.max(), peak > 0, let last = recent.last,
              let peakIndex = recent.firstIndex(of: peak) else { return nil }
        let tail = recent[peakIndex...]
        guard tail.count >= 2, isMonotoneNonIncreasing(tail) else { return nil }
        return Downtrend(name: lift.name, peak: peak, last: last, decline: (peak - last) / peak)
    }

    private static func isMonotoneNonIncreasing(_ values: ArraySlice<Double>) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 >= $1 }
    }
}
