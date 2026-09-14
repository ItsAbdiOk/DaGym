import Foundation
import GymCore

/// One planned day in the snapshot's look-ahead. The widget needs a week of these because its
/// timeline outlives the write: an entry that renders on Tuesday must show Tuesday's routine,
/// not whatever was scheduled the last time the app happened to be open.
struct WidgetDayPlan: Codable, Equatable {
    /// Start of that calendar day, in the calendar the app wrote with.
    var date: Date
    var routineName: String?
    var exerciseCount: Int
    /// SF Symbol name + `RoutineTint` raw value — see `RoutineGlyph` in the app target.
    var routineSymbolName: String?
    var routineTint: String?
}

/// Everything one timeline entry actually renders, resolved for a particular day.
struct ResolvedWidgetDay: Equatable {
    /// False before the app has ever written a snapshot. The widget must say so rather than
    /// confidently rendering "Rest Day · 0 EXERCISES" over an empty store.
    var hasData: Bool
    var routineName: String?
    var exerciseCount: Int
    var routineSymbolName: String?
    var routineTint: String?
    var streakWeeks: Int
    /// The 7 days ending on (and including) the entry's day, oldest first.
    var trainedDays: [Bool]
}

/// What `TodayWorkoutWidget` / `StreakWidget` read. Written by the app (`WidgetSnapshotWriter`)
/// after every finish/schedule change; the widgets never open the SwiftData store themselves.
/// Shared verbatim between the `DaGym` and `DaGymWidgets` targets (see `project.yml`).
///
/// It carries a *week* of plan plus the raw workout days rather than a single pre-rendered
/// "today", because WidgetKit renders entries the app is not awake for: with one baked-in day a
/// lifter who trained Monday and didn't open the app still saw "TODAY / Push A" on Wednesday, and
/// the streak could never decay. `resolved(on:)` is the one place a day is turned into pixels —
/// the provider calls it per entry, and `WidgetSnapshotTests` calls it across midnight.
///
/// Every field added after the first ship decodes with a default (see `init(from:)`) so an old
/// widget binary can still read a newer app's snapshot, and vice versa.
struct WidgetSnapshot: Codable, Equatable {
    var routineName: String?
    var exerciseCount: Int
    var streakWeeks: Int
    /// The last 7 calendar days as of `updatedAt`, oldest first.
    var trainedDays: [Bool]
    var updatedAt: Date
    var routineSymbolName: String?
    var routineTint: String?
    /// Today plus the next several days, so entries past midnight have something true to show.
    var days: [WidgetDayPlan]
    /// Start-of-day of every finished workout in recent history — enough to redraw the dot row
    /// and recompute the weekly streak (via `GymCore.Streaks`) for any day in `days`.
    var workoutDays: [Date]
    var weeklyGoal: Int
    var weekStartsMonday: Bool
    /// `DGAccent` and `Preferences.Appearance` raw values, so the widget and the Live Activity
    /// stop hard-coding coral-on-black while the app is themed something else.
    var accent: String
    var appearance: String

    init(
        routineName: String?, exerciseCount: Int, streakWeeks: Int, trainedDays: [Bool],
        updatedAt: Date, routineSymbolName: String? = nil, routineTint: String? = nil,
        days: [WidgetDayPlan] = [], workoutDays: [Date] = [], weeklyGoal: Int = 4,
        weekStartsMonday: Bool = true, accent: String = "coral", appearance: String = "system"
    ) {
        self.routineName = routineName
        self.exerciseCount = exerciseCount
        self.streakWeeks = streakWeeks
        self.trainedDays = trainedDays
        self.updatedAt = updatedAt
        self.routineSymbolName = routineSymbolName
        self.routineTint = routineTint
        self.days = days
        self.workoutDays = workoutDays
        self.weeklyGoal = weeklyGoal
        self.weekStartsMonday = weekStartsMonday
        self.accent = accent
        self.appearance = appearance
    }

    /// Hand-written so a snapshot missing any of the later keys still decodes: Swift's synthesized
    /// `init(from:)` ignores property defaults and would throw instead.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        routineName = try values.decodeIfPresent(String.self, forKey: .routineName)
        exerciseCount = try values.decodeIfPresent(Int.self, forKey: .exerciseCount) ?? 0
        streakWeeks = try values.decodeIfPresent(Int.self, forKey: .streakWeeks) ?? 0
        trainedDays = try values.decodeIfPresent([Bool].self, forKey: .trainedDays)
            ?? Array(repeating: false, count: 7)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        routineSymbolName = try values.decodeIfPresent(String.self, forKey: .routineSymbolName)
        routineTint = try values.decodeIfPresent(String.self, forKey: .routineTint)
        days = try values.decodeIfPresent([WidgetDayPlan].self, forKey: .days) ?? []
        workoutDays = try values.decodeIfPresent([Date].self, forKey: .workoutDays) ?? []
        weeklyGoal = try values.decodeIfPresent(Int.self, forKey: .weeklyGoal) ?? 4
        weekStartsMonday = try values.decodeIfPresent(Bool.self, forKey: .weekStartsMonday) ?? true
        accent = try values.decodeIfPresent(String.self, forKey: .accent) ?? "coral"
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
    }

    static let empty = WidgetSnapshot(
        routineName: nil, exerciseCount: 0, streakWeeks: 0,
        trainedDays: Array(repeating: false, count: 7), updatedAt: .distantPast
    )

    /// False until the app has written at least once — the widget's "Open DaGym to set up" case.
    var hasData: Bool { updatedAt != .distantPast }

    /// The same week definition the app uses (`Preferences.trainingCalendar`), so the widget's
    /// streak can never disagree with Home's.
    var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsMonday ? 2 : 1
        return calendar
    }

    /// Everything one entry renders, computed for `date` rather than for write time.
    func resolved(on date: Date) -> ResolvedWidgetDay {
        guard hasData else {
            return ResolvedWidgetDay(
                hasData: false, routineName: nil, exerciseCount: 0, routineSymbolName: nil,
                routineTint: nil, streakWeeks: 0, trainedDays: Array(repeating: false, count: 7)
            )
        }
        let calendar = calendar
        let plan = days.first { calendar.isDate($0.date, inSameDayAs: date) }
        // No plan for this day means either the timeline outran the look-ahead or the snapshot
        // predates `days` entirely. Either way, fall back to the day the snapshot was written for
        // rather than inventing a rest day out of a missing entry.
        let useStored = plan == nil
        // An older snapshot (or a preview) carries no day-level history; its baked-in streak is
        // the best available answer, and is still right for the day it was written.
        let streak = workoutDays.isEmpty
            ? streakWeeks
            : GymCore.Streaks.weekly(
                workoutDates: workoutDays, weeklyGoal: weeklyGoal, calendar: calendar, now: date
            ).current
        return ResolvedWidgetDay(
            hasData: true,
            routineName: useStored ? routineName : plan?.routineName,
            exerciseCount: useStored ? exerciseCount : (plan?.exerciseCount ?? 0),
            routineSymbolName: useStored ? routineSymbolName : plan?.routineSymbolName,
            routineTint: useStored ? routineTint : plan?.routineTint,
            streakWeeks: streak,
            trainedDays: Self.trainedDays(workoutDays, endingOn: date, calendar: calendar)
        )
    }

    /// `now`, then each following local midnight this snapshot still has a plan for — one
    /// timeline entry each. Lives here rather than in the widget target so it is reachable from
    /// `DaGymTests`, which can only see the app target.
    func entryDates(from now: Date) -> [Date] {
        guard days.count > 1 else { return [now] }
        let calendar = calendar
        let startOfToday = calendar.startOfDay(for: now)
        var dates = [now]
        for offset in 1..<days.count {
            guard let midnight = calendar.date(byAdding: .day, value: offset, to: startOfToday) else {
                break
            }
            dates.append(midnight)
        }
        return dates
    }

    /// When WidgetKit should come back for a fresh timeline: the last of `dates`, but only if it
    /// is still ahead of `now`. A timeline whose only entry is `now` (no look-ahead — a fresh
    /// install, or a snapshot from a build that predates `days`) has nothing date-dependent in
    /// it, and `.after(now)` is already in the past by the time WidgetKit reads it, so it
    /// reloaded immediately and burned the daily budget on nothing. Nil means "never": the app
    /// reloads the timeline itself when it writes a new snapshot. Lives here, not in the widget
    /// target, so `DaGymTests` can reach it.
    static func reloadDate(after dates: [Date], now: Date) -> Date? {
        guard let last = dates.last, last > now else { return nil }
        return last
    }

    /// The 7 days ending on `date`, oldest first, `true` where a finished workout landed.
    static func trainedDays(_ workoutDays: [Date], endingOn date: Date, calendar: Calendar) -> [Bool] {
        (0..<7).reversed().map { offset -> Bool in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return false }
            return workoutDays.contains { calendar.isDate($0, inSameDayAs: day) }
        }
    }
}

/// Reads/writes `WidgetSnapshot` to the App Group's shared `UserDefaults` suite.
enum WidgetSnapshotStore {
    static let appGroupID = "group.dev.abdirahmanmohamed.dagym"
    private static let key = "widgetSnapshot"

    /// `nil` when the App Group container isn't available (e.g. the entitlement is missing on a
    /// developer's ad-hoc build) — callers should no-op rather than crash.
    static var appGroupSuite: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(_ snapshot: WidgetSnapshot, to suite: UserDefaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        suite.set(data, forKey: key)
    }

    static func read(from suite: UserDefaults) -> WidgetSnapshot {
        guard let data = suite.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
