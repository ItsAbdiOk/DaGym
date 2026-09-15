import Foundation

/// Planned-vs-kept over a trailing window of days, for the training digest and the "how
/// consistent was I" tool. The same day-by-day judgement `CoachRules.adherenceDropCards`
/// makes (`schedule.routineIDs(on:)` non-empty = planned; a logged workout that day = kept),
/// over a plain trailing window rather than complete calendar weeks, so "the last 4 weeks"
/// means the last 28 days.
public struct AdherenceSummary: Hashable, Sendable {
    public var planned: Int
    public var kept: Int
    public var weeks: Int

    public init(planned: Int, kept: Int, weeks: Int) {
        self.planned = planned
        self.kept = kept
        self.weeks = weeks
    }

    /// Whole-number percent, nil when nothing was planned in the window.
    public var percent: Int? {
        guard planned > 0 else { return nil }
        return Int((Double(kept) / Double(planned) * 100).rounded())
    }

    public static func over(
        weeks: Int, schedule: WeeklySchedule, loggedWorkoutDates: [Date], now: Date, calendar: Calendar
    ) -> AdherenceSummary {
        let trained = Set(loggedWorkoutDates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        var summary = AdherenceSummary(planned: 0, kept: 0, weeks: weeks)
        for offset in 0..<(weeks * 7) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  !schedule.routineIDs(on: day, calendar: calendar).isEmpty else { continue }
            summary.planned += 1
            if trained.contains(day) { summary.kept += 1 }
        }
        return summary
    }
}
