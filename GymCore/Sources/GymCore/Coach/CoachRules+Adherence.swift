import Foundation

/// Adherence-drop rule: reuses `WeeklySchedule.routineIDs(on:calendar:)` — the lifter's own
/// recurring plan — as the "planned" side, so this is a drop against their own schedule, not a
/// generic weekly-goal count (that's what `Streaks` already covers elsewhere).
extension CoachRules {
    static func adherenceDropCards(input: CoachInput, now: Date, calendar: Calendar) -> [CoachCard] {
        let lookback = TrainingConstants.coachAdherenceLookbackWeeks
        guard lookback >= 4, lookback.isMultiple(of: 2) else { return [] }
        let half = lookback / 2
        let starts = completeWeekStarts(before: now, count: lookback, calendar: calendar)
        guard starts.count == lookback else { return [] }

        let rates = starts.compactMap { start -> Double? in
            let planned = plannedDays(weekStart: start, schedule: input.schedule, calendar: calendar)
            guard planned > 0 else { return nil }
            let actual = actualDays(weekStart: start, dates: input.workoutDates, calendar: calendar)
            return Double(actual) / Double(planned)
        }
        guard rates.count == lookback else { return [] }

        let recent = Array(rates.prefix(half))
        let prior = Array(rates.suffix(half))
        let recentRate = recent.reduce(0, +) / Double(half)
        let priorRate = prior.reduce(0, +) / Double(half)
        guard priorRate > 0 else { return [] }
        let drop = (priorRate - recentRate) / priorRate
        guard drop >= TrainingConstants.coachAdherenceDropFraction else { return [] }

        let action = mostMissedWeekday(
            weekStarts: Array(starts.prefix(half)), schedule: input.schedule,
            dates: input.workoutDates, calendar: calendar
        ).map(CoachSuggestedAction.addSession) ?? .none

        let evidence: [CoachEvidenceItem] = [
            .init("Recent completion rate", .number(recentRate)),
            .init("Prior completion rate", .number(priorRate)),
            .init("Weeks compared", .count(half))
        ]
        return [CoachCard(
            rule: .adherenceDrop, severity: .notice, title: "Adherence is slipping",
            body: "You've completed fewer of your planned sessions the last \(half) weeks than the "
                + "\(half) before that.",
            evidence: evidence, suggestedAction: action,
            distinguishingKey: DateKey.string(for: starts[0], calendar: calendar), firedDate: now
        )]
    }

    /// The `count` most recent *complete* calendar weeks before `now`'s own week, most recent
    /// first — the in-progress week is excluded since it hasn't had a chance to fill up yet.
    private static func completeWeekStarts(before now: Date, count: Int, calendar: Calendar) -> [Date] {
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var starts: [Date] = []
        var cursor = thisWeekStart
        for _ in 0..<count {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            starts.append(previous)
            cursor = previous
        }
        return starts
    }

    private static func plannedDays(weekStart: Date, schedule: WeeklySchedule, calendar: Calendar) -> Int {
        (0..<7).reduce(0) { total, offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return total }
            return total + (schedule.routineIDs(on: day, calendar: calendar).isEmpty ? 0 : 1)
        }
    }

    private static func actualDays(weekStart: Date, dates: [Date], calendar: Calendar) -> Int {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return 0 }
        let days = Set(dates.filter { $0 >= weekStart && $0 < weekEnd }.map { calendar.startOfDay(for: $0) })
        return days.count
    }

    /// The planned weekday with the most misses across `weekStarts` — the natural "add a session
    /// here" suggestion for the adherence card.
    private static func mostMissedWeekday(
        weekStarts: [Date], schedule: WeeklySchedule, dates: [Date], calendar: Calendar
    ) -> Weekday? {
        let workoutDays = Set(dates.map { calendar.startOfDay(for: $0) })
        var misses: [Weekday: Int] = [:]
        for start in weekStarts {
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                      let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
                      !schedule.routineIDs(on: day, calendar: calendar).isEmpty,
                      !workoutDays.contains(calendar.startOfDay(for: day)) else { continue }
                misses[weekday, default: 0] += 1
            }
        }
        return misses.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }?.key
    }
}
