import Foundation

/// The Sunday check-in: which week a review is about, whether one is due, and the canned
/// user turn that asks the coach for it. The review itself is an ordinary chat turn — same
/// tools, same proposals, same second opinion — so nothing new goes over the wire.
public enum CoachWeekReview {
    /// Home shows the card only when the lifter trained at least this often in the week.
    public static let minimumWorkouts = 2

    /// The Sunday that ends the week under review: today when today is Sunday, else the most
    /// recent one. Midnight in `calendar`, so two calls on the same day agree.
    public static func weekEnding(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        // Sunday is weekday 1 whatever `firstWeekday` says.
        let daysSinceSunday = weekday - 1
        return calendar.date(byAdding: .day, value: -daysSinceSunday, to: today) ?? today
    }

    /// "2026-09-13" — the key Preferences and the archive file a review under.
    public static func weekKey(now: Date, calendar: Calendar) -> String {
        DateKey.string(for: weekEnding(now: now, calendar: calendar), calendar: calendar)
    }

    /// The Monday that starts the week ending on `weekEnding`.
    public static func weekStart(weekEnding: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -6, to: weekEnding) ?? weekEnding
    }

    /// Workouts in the seven days ending on `weekEnding` (inclusive of that whole day).
    public static func workoutCount(dates: [Date], weekEnding: Date, calendar: Calendar) -> Int {
        let start = weekStart(weekEnding: weekEnding, calendar: calendar)
        guard let end = calendar.date(byAdding: .day, value: 1, to: weekEnding) else { return 0 }
        return dates.filter { $0 >= start && $0 < end }.count
    }

    /// What Home decides from: the week's key and count plus what has already happened to it.
    public struct Status: Hashable, Sendable {
        public var weekKey: String
        public var workoutCount: Int
        public var isConfigured: Bool
        public var hasThread: Bool
        public var dismissedWeekKey: String?
        public var lastReviewedWeekKey: String?

        public init(
            weekKey: String, workoutCount: Int, isConfigured: Bool, hasThread: Bool,
            dismissedWeekKey: String? = nil, lastReviewedWeekKey: String? = nil
        ) {
            self.weekKey = weekKey
            self.workoutCount = workoutCount
            self.isConfigured = isConfigured
            self.hasThread = hasThread
            self.dismissedWeekKey = dismissedWeekKey
            self.lastReviewedWeekKey = lastReviewedWeekKey
        }

        /// The lifter said "not this week".
        public var isDismissed: Bool { dismissedWeekKey == weekKey }

        /// A review should be offered: the chat can send, the week had enough training, and
        /// nothing has been started, done or dismissed for it yet.
        public var isDue: Bool {
            isConfigured && workoutCount >= minimumWorkouts && !hasThread && !isDismissed
                && lastReviewedWeekKey != weekKey
        }

        /// The card has something to show: a review to offer, or one under way or done.
        public var isVisible: Bool { isConfigured && !isDismissed && (isDue || hasThread) }
    }
}

/// The canned user turn a week review sends. Fixed wording so the coach gets the same brief
/// every Sunday and a test can pin it.
public enum CoachWeekReviewPrompt {
    public static func userTurn(weekEnding: Date, calendar: Calendar) -> String {
        let start = CoachWeekReview.weekStart(weekEnding: weekEnding, calendar: calendar)
        let range = "\(DateKey.string(for: start, calendar: calendar)) to "
            + "\(DateKey.string(for: weekEnding, calendar: calendar))"
        return """
        Weekly check-in for \(range). Review my training this week against the weeks before it. \
        Read the sessions I logged in that window (get_recent_workouts, then get_workout for each), \
        the history of the main lifts I did (get_exercise_history), my weekly and per-muscle volume \
        (get_weekly_volume, get_muscle_volume), adherence and recovery. Then tell me, in under 200 \
        words with no headings: what progressed (which lifts, which numbers), what stalled or slipped, \
        and one concrete tweak for next week. Make that tweak a real proposal through the matching \
        propose_* tool (a swap, a deload, a schedule change or a routine change) so I can apply it \
        with one tap — one proposal, not several. If nothing needs changing, say so and skip the proposal.
        """
    }

    /// The first line of the coach's reply, trimmed for a card — "Bench moved from 80 to 82.5 kg…".
    public static func headline(from reply: String, maxLength: Int = 120) -> String? {
        let line = reply.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > maxLength ? String(line.prefix(maxLength - 1)) + "…" : line
    }
}
