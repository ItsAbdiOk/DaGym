import Foundation

/// Session-drift rule: recent sessions' completed/planned set ratio and average duration,
/// compared against the baseline window right before them — no new math, just an average over
/// `CoachSessionSummary`, which the app layer already builds from the routine plan + the logged
/// workout.
extension CoachRules {
    static func sessionDriftCards(input: CoachInput, now: Date) -> [CoachCard] {
        let sessions = input.recentSessions.sorted { $0.date < $1.date }
        let recentCount = TrainingConstants.coachDriftRecentSessions
        let baselineCount = TrainingConstants.coachDriftBaselineSessions
        guard sessions.count >= recentCount + baselineCount else { return [] }

        let recent = Array(sessions.suffix(recentCount))
        let baseline = Array(sessions.suffix(recentCount + baselineCount).prefix(baselineCount))
        guard let mostRecent = recent.last else { return [] }

        let recentSetRatio = averageSetRatio(recent)
        let baselineSetRatio = averageSetRatio(baseline)
        let recentDuration = averageDuration(recent)
        let baselineDuration = averageDuration(baseline)
        guard baselineSetRatio > 0, baselineDuration > 0 else { return [] }

        let setDrop = (baselineSetRatio - recentSetRatio) / baselineSetRatio
        let durationDrop = (baselineDuration - recentDuration) / baselineDuration
        let threshold = TrainingConstants.coachDriftDropFraction
        guard setDrop >= threshold || durationDrop >= threshold else { return [] }

        let evidence: [CoachEvidenceItem] = [
            .init("Recent set completion", .number(recentSetRatio)),
            .init("Baseline set completion", .number(baselineSetRatio)),
            .init("Recent avg duration (s)", .count(Int(recentDuration))),
            .init("Baseline avg duration (s)", .count(Int(baselineDuration)))
        ]
        return [CoachCard(
            rule: .sessionDrift, severity: .notice, title: "Sessions are trending shorter",
            body: "Your last \(recentCount) sessions are completing fewer sets or running shorter "
                + "than your usual \(baselineCount)-session baseline.",
            evidence: evidence, suggestedAction: .none,
            distinguishingKey: dateKey(mostRecent.date), firedDate: now
        )]
    }

    private static func averageSetRatio(_ sessions: [CoachSessionSummary]) -> Double {
        let ratios = sessions.compactMap { session -> Double? in
            guard session.plannedSetCount > 0 else { return nil }
            return Double(session.completedSetCount) / Double(session.plannedSetCount)
        }
        guard !ratios.isEmpty else { return 0 }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    private static func averageDuration(_ sessions: [CoachSessionSummary]) -> Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(sessions.reduce(0) { $0 + $1.durationSeconds }) / Double(sessions.count)
    }
}
