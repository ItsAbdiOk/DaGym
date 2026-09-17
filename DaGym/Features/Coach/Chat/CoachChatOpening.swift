import Foundation
import GymCore

/// The words the pushed chat screen puts around the transcript, kept pure so a test can pin
/// them: the header's subtitle (whether a weekly review is waiting, and what the coach has
/// cost), the opening bubble on an empty thread, and the chips under it.
enum CoachChatOpening {
    /// "Weekly review · $0.14 this month". The ledger has no month buckets — it counts from
    /// first use or the last reset — so the spend is "this month" only when that start falls
    /// inside the current month, and "since Jun" otherwise rather than a number that isn't.
    static func subtitle(
        reviewDue: Bool, ledger: CoachChatUsageLedger, now: Date, calendar: Calendar
    ) -> String {
        let spend = spendLine(ledger: ledger, now: now, calendar: calendar)
        return reviewDue ? "Weekly review · \(spend)" : spend
    }

    static func spendLine(ledger: CoachChatUsageLedger, now: Date, calendar: Calendar) -> String {
        guard let since = ledger.since, !ledger.isEmpty else { return "$0.00 this month" }
        let amount = CoachUsageText.cost(ledger.estimatedUSD(), reported: ledger.isFullyReported)
            ?? "\(CoachUsageText.tokens(ledger.totalTokens)) tokens"
        if calendar.isDate(since, equalTo: now, toGranularity: .month) {
            return "\(amount) this month"
        }
        let month = since.formatted(Date.FormatStyle(calendar: calendar).month(.abbreviated))
        return "\(amount) since \(month)"
    }

    /// The assistant bubble an empty thread opens with, built from the real week:
    /// "Your week is done: 3 of 4 sessions, 47,200 kg of volume, one PR. Want the review?"
    /// `volume` is already formatted in the lifter's unit.
    static func line(recap: WeeklyRecap, reviewDue: Bool, volume: String) -> String {
        guard recap.workouts > 0 else {
            return "Nothing logged this week yet. Ask me anything about your training, or start "
                + "a session and I'll read it afterwards."
        }
        let lead = reviewDue ? "Your week is done" : "Your week so far"
        let sessions = "\(recap.workouts) of \(recap.weeklyGoal) sessions"
        let prs = switch recap.prs {
        case 0: "no PRs"
        case 1: "one PR"
        default: "\(recap.prs) PRs"
        }
        let ask = reviewDue ? "Want the review?" : "What would you like to look at?"
        return "\(lead): \(sessions), \(volume) of volume, \(prs). \(ask)"
    }

    /// The chips under the transcript: "Review my week" leads when a review is waiting, then
    /// the three standing prompts.
    static func chips(reviewDue: Bool) -> [String] {
        reviewDue ? [reviewChip] + CoachChatSuggestedPrompts.all : CoachChatSuggestedPrompts.all
    }

    static let reviewChip = "Review my week"
}
