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

        // Only weeks the *current* schedule actually describes are scored — see
        // `CoachInput.scheduleUpdatedAt`. A week that began before the lifter last edited their
        // plan was lived under a different plan, and grading it against today's one silently
        // rewrote their adherence history every time they moved a training day.
        guard starts.allSatisfy({ describesWeek(start: $0, updatedAt: input.scheduleUpdatedAt) }) else {
            return []
        }
        let trained = Set(input.loggedWorkoutDates.map { calendar.startOfDay(for: $0) })
        let rates = starts.compactMap { start -> Double? in
            let days = plannedAndKept(weekStart: start, schedule: input.schedule, trained: trained,
                                      calendar: calendar)
            guard days.planned > 0 else { return nil }
            return Double(days.kept) / Double(days.planned)
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
            trained: trained, calendar: calendar
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

    /// Whether the current schedule can fairly be said to describe the week starting at
    /// `start`: either we don't know when it was last edited, or it was already in force when
    /// that week began.
    private static func describesWeek(start: Date, updatedAt: Date?) -> Bool {
        guard let updatedAt else { return true }
        return updatedAt <= start
    }

    /// The week's planned training days, and how many of those *same* days were actually
    /// trained.
    ///
    /// The old version compared "days planned" with "days trained anywhere in the week", so
    /// three unplanned drop-ins against three planned days read as 100% adherence while every
    /// planned session was missed, and five trained days against three planned gave a
    /// completion "rate" of 1.67 — which then poisoned the recent-vs-prior average the rule
    /// compares. Scoring the intersection keeps every rate inside 0…1 and makes it mean what
    /// the card says it means: the share of *planned* sessions kept.
    private static func plannedAndKept(
        weekStart: Date, schedule: WeeklySchedule, trained: Set<Date>, calendar: Calendar
    ) -> (planned: Int, kept: Int) {
        (0..<7).reduce(into: (planned: 0, kept: 0)) { total, offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart),
                  !schedule.routineIDs(on: day, calendar: calendar).isEmpty else { return }
            total.planned += 1
            if trained.contains(calendar.startOfDay(for: day)) { total.kept += 1 }
        }
    }

    /// The planned weekday with the most misses across `weekStarts` — the natural "add a session
    /// here" suggestion for the adherence card.
    private static func mostMissedWeekday(
        weekStarts: [Date], schedule: WeeklySchedule, trained: Set<Date>, calendar: Calendar
    ) -> Weekday? {
        let workoutDays = trained
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
