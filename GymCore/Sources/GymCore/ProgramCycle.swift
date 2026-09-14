import Foundation

/// Where a multi-week program sits in its cycle, measured in **whole calendar weeks** rather
/// than 7-day blocks from an instant.
///
/// The old arithmetic was `dateComponents([.day], from: startedAt, to: Date()) / 7`, which
/// anchors every week boundary to the *time of day* the program was started: a program begun
/// on a Wednesday at 21:30 rolled over mid-Wednesday-evening, so a Wednesday 18:00 session and
/// a Wednesday 22:00 session landed in different program weeks, a planned deload straddled two
/// calendar weeks, and flying London → LA moved the boundary by eight hours. It also ignored
/// the lifter's `weekStartsMonday` preference entirely.
///
/// Everything here is pure over `(startedAt, now, calendar, weeks)` — no `Date()`, no
/// `Calendar.current` — so the app layer decides which calendar (and so which first weekday)
/// a program's weeks are measured in, and a test can pin both.
public enum ProgramCycle {
    /// How many times a program repeats its own week block before it is considered finished.
    ///
    /// Without a cap the week index wrapped forever and the cycle index climbed without bound,
    /// so the training-max rule kept bumping every `weeks` weeks for as long as the program
    /// stayed active — years, in principle. A program is a block you run a few times and then
    /// re-plan, so after `maxCycles` runs it completes instead.
    public static let maxCycles = 4

    /// The start of the calendar week containing `date`, in `calendar` (which carries the
    /// lifter's first-weekday preference).
    public static func weekStart(of date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    /// Whole calendar weeks between the week containing `startedAt` and the week containing
    /// `now`. Zero for anything inside the starting week, and never negative.
    ///
    /// Measured between two week *starts*, so it is immune to time-of-day, to a timezone
    /// change, and to a DST changeover in between (the day difference across a 23- or 25-hour
    /// day is still a whole number of days).
    public static func weeksElapsed(from startedAt: Date, to now: Date, calendar: Calendar) -> Int {
        guard let start = weekStart(of: startedAt, calendar: calendar),
              let end = weekStart(of: now, calendar: calendar) else { return 0 }
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days / 7)
    }

    /// The 1-based week within the block and the 1-based repetition of the block, or `nil` once
    /// the program has run `maxCycles` blocks (or has a non-positive `weeks`).
    public static func position(
        startedAt: Date, now: Date, weeks: Int, calendar: Calendar
    ) -> (week: Int, cycle: Int)? {
        guard weeks > 0 else { return nil }
        let elapsed = weeksElapsed(from: startedAt, to: now, calendar: calendar)
        let cycle = elapsed / weeks
        guard cycle < maxCycles else { return nil }
        return (elapsed % weeks + 1, cycle + 1)
    }

    /// Whether the program has run its full `maxCycles` blocks and should be completed.
    public static func isFinished(startedAt: Date, now: Date, weeks: Int, calendar: Calendar) -> Bool {
        guard weeks > 0 else { return false }
        return weeksElapsed(from: startedAt, to: now, calendar: calendar) / weeks >= maxCycles
    }

    /// `startedAt` moved forward by `weeks` whole calendar weeks, never past `limit`.
    ///
    /// Used when a planned deload week hands control back: the interrupted program has to skip
    /// forward by however long the deload ran, or it resumes at the week the deload consumed —
    /// which for a 4-week block interrupted in week 3 is week 4, the block's *own* deload, so
    /// the lifter gets two deload weeks back to back and never trains week 3 at all.
    public static func shifted(
        _ startedAt: Date, byWeeks weeks: Int, notPast limit: Date, calendar: Calendar
    ) -> Date {
        guard weeks > 0,
              let moved = calendar.date(byAdding: .day, value: weeks * 7, to: startedAt)
        else { return startedAt }
        return min(moved, limit)
    }
}
