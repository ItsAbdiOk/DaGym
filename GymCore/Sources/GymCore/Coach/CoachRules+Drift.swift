import Foundation

/// Session-drift rule: recent sessions' completed/planned set ratio and average duration,
/// compared against the baseline window right before them — no new math, just an average over
/// `CoachSessionSummary`, which the app layer already builds from the routine plan + the logged
/// workout.
///
/// Two kinds of session carry no signal and are skipped rather than averaged in: one with no
/// plan behind it (a freestyle session, `plannedSetCount == 0`) has no set ratio, and one longer
/// than `TrainingConstants.coachDriftMaxSessionSeconds` was left open rather than trained long,
/// so its duration would inflate whichever window it lands in.
extension CoachRules {
    static func sessionDriftCards(input: CoachInput, now: Date, calendar: Calendar) -> [CoachCard] {
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

        let threshold = TrainingConstants.coachDriftDropFraction
        let setDrop = baselineSetRatio > 0 ? (baselineSetRatio - recentSetRatio) / baselineSetRatio : 0
        let durationDrop = baselineDuration > 0 && recentDuration > 0
            ? (baselineDuration - recentDuration) / baselineDuration
            : 0
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
            distinguishingKey: weekKey(mostRecent.date, calendar: calendar), firedDate: now
        )]
    }

    /// The week the newest session falls in, not the session's own timestamp. Drift is a
    /// weeks-long shape; keying on the exact date meant every new session minted a new
    /// fingerprint and a dismissed card returned the next time the lifter trained.
    private static func weekKey(_ date: Date, calendar: Calendar) -> String {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return DateKey.string(for: start, calendar: calendar)
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
        let durations = sessions
            .map(\.durationSeconds)
            .filter { $0 > 0 && $0 <= TrainingConstants.coachDriftMaxSessionSeconds }
        guard !durations.isEmpty else { return 0 }
        return Double(durations.reduce(0, +)) / Double(durations.count)
    }
}
