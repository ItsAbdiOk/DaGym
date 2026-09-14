import Foundation
import Testing

@testable import DaGym

@Suite("Widget snapshot persistence")
struct WidgetSnapshotTests {
    /// A fresh, isolated `UserDefaults` suite per test (mirrors `PreferencesTests`).
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("encodes and decodes round trip through an isolated UserDefaults suite")
    func roundTrips() throws {
        let suite = makeSuite(#function)
        let snapshot = WidgetSnapshot(
            routineName: "Push Day A", exerciseCount: 5, streakWeeks: 3,
            trainedDays: [true, false, true, true, false, false, true],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        WidgetSnapshotStore.write(snapshot, to: suite)
        let read = WidgetSnapshotStore.read(from: suite)

        #expect(read == snapshot)
    }

    @Test("a rest-day snapshot (nil routine name) round trips too")
    func roundTripsRestDay() throws {
        let suite = makeSuite(#function)
        let snapshot = WidgetSnapshot(
            routineName: nil, exerciseCount: 0, streakWeeks: 0,
            trainedDays: Array(repeating: false, count: 7), updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        WidgetSnapshotStore.write(snapshot, to: suite)
        #expect(WidgetSnapshotStore.read(from: suite) == snapshot)
    }

    @Test("reading an empty suite returns the documented empty snapshot")
    func emptySuiteReadsEmpty() throws {
        let suite = makeSuite(#function)
        #expect(WidgetSnapshotStore.read(from: suite) == WidgetSnapshot.empty)
    }

    @Test("the routine glyph round trips too")
    func routineGlyphRoundTrips() throws {
        let suite = makeSuite(#function)
        let snapshot = WidgetSnapshot(
            routineName: "Push Day A", exerciseCount: 5, streakWeeks: 3,
            trainedDays: [true, false, true, true, false, false, true],
            updatedAt: Date(timeIntervalSince1970: 1_000),
            routineSymbolName: "bolt", routineTint: "violet"
        )

        WidgetSnapshotStore.write(snapshot, to: suite)
        let read = WidgetSnapshotStore.read(from: suite)

        #expect(read == snapshot)
        #expect(read.routineSymbolName == "bolt")
        #expect(read.routineTint == "violet")
    }

    @Test("decoding a snapshot written before the glyph existed leaves it nil, not a decode failure")
    func decodingPreGlyphSnapshotDefaultsToNil() throws {
        let suite = makeSuite(#function)
        // What an older app build wrote: no `routineSymbolName`/`routineTint` keys at all.
        let legacyJSON = """
        {"routineName":"Push Day A","exerciseCount":5,"streakWeeks":3,
        "trainedDays":[true,false,true,true,false,false,true],"updatedAt":1000}
        """
        suite.set(Data(legacyJSON.utf8), forKey: "widgetSnapshot")

        let read = WidgetSnapshotStore.read(from: suite)
        #expect(read.routineName == "Push Day A")
        #expect(read.routineSymbolName == nil)
        #expect(read.routineTint == nil)
        // The later fields fall back rather than failing the whole decode.
        #expect(read.days.isEmpty)
        #expect(read.accent == "coral")
        #expect(read.appearance == "system")
        #expect(read.weeklyGoal == 4)
    }
}

/// Finding 3: the provider emitted ONE entry with `.never` and the snapshot baked in "today".
/// A lifter who trained Monday and didn't open the app read "TODAY / Push A / 5 EXERCISES" all
/// day Tuesday and Wednesday, and the streak could never decay. These walk the same functions the
/// widget's timeline walks, across midnight.
@MainActor
@Suite("Widget timeline across midnight")
struct WidgetTimelineTests {
    private static func calendar(mondayFirst: Bool = true) -> Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = mondayFirst ? 2 : 1
        return calendar
    }

    /// A snapshot written "today" with a different routine on each of the next few days.
    private func snapshot(
        now: Date, plans: [String?], workoutDays: [Date] = [], weeklyGoal: Int = 2
    ) -> WidgetSnapshot {
        let calendar = Self.calendar()
        let startOfToday = calendar.startOfDay(for: now)
        let days = plans.enumerated().compactMap { offset, name -> WidgetDayPlan? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfToday) else {
                return nil
            }
            return WidgetDayPlan(
                date: date, routineName: name, exerciseCount: name == nil ? 0 : 5,
                routineSymbolName: name == nil ? nil : "dumbbell", routineTint: name == nil ? nil : "coral"
            )
        }
        return WidgetSnapshot(
            routineName: plans.first.flatMap { $0 }, exerciseCount: 5, streakWeeks: 0,
            trainedDays: Array(repeating: false, count: 7), updatedAt: now,
            days: days, workoutDays: workoutDays, weeklyGoal: weeklyGoal
        )
    }

    @Test("one entry per upcoming midnight, not a single entry that never expires")
    func emitsAnEntryPerMidnight() throws {
        let now = Date()
        let snapshot = snapshot(now: now, plans: ["Push A", nil, "Pull B"])

        let dates = snapshot.entryDates(from: now)

        #expect(dates.count == 3)
        #expect(dates[0] == now)
        let calendar = Self.calendar()
        for (offset, date) in dates.enumerated().dropFirst() {
            #expect(date == calendar.startOfDay(for: date))
            let expected = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
            #expect(date == expected)
        }
    }

    @Test("tomorrow's entry renders tomorrow's routine, not the one baked in at write time")
    func tomorrowRendersTomorrow() throws {
        let now = Date()
        let snapshot = snapshot(now: now, plans: ["Push A", nil, "Pull B"])
        let dates = snapshot.entryDates(from: now)

        #expect(snapshot.resolved(on: dates[0]).routineName == "Push A")
        // Tuesday is a rest day in this plan — the old widget still said "Push A · 5 EXERCISES".
        #expect(snapshot.resolved(on: dates[1]).routineName == nil)
        #expect(snapshot.resolved(on: dates[1]).exerciseCount == 0)
        #expect(snapshot.resolved(on: dates[2]).routineName == "Pull B")
    }

    @Test("the 7-day dot row slides with the entry's day")
    func dotRowSlides() throws {
        let calendar = Self.calendar()
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let snapshot = snapshot(now: now, plans: ["Push A", nil, nil], workoutDays: [today])

        // Today: trained today, so the last dot is lit.
        #expect(snapshot.resolved(on: now).trainedDays.last == true)
        // Two days on: that same workout has slid back two places and the last dot is dark.
        let dates = snapshot.entryDates(from: now)
        let later = snapshot.resolved(on: dates[2]).trainedDays
        #expect(later.last == false)
        #expect(later[4])
    }

    /// `WidgetSnapshotProvider.reloadPolicy` asks WidgetKit back `.after` the last entry only
    /// when that entry is in the future, and `.never` otherwise. This pins the input side of
    /// that rule: a snapshot with no look-ahead (nothing written yet, or written by a build
    /// before `days`) has exactly one entry, `now` — which is why `.after(entries.last)` was a
    /// reload loop for it, and why the policy has to look at the date rather than the count.
    @Test("a snapshot with no look-ahead has one entry at `now` and nothing after it")
    func noLookAheadMeansASingleEntryAtNow() throws {
        let now = Date()

        let empty = WidgetSnapshot.empty.entryDates(from: now)
        #expect(empty == [now])

        let legacy = WidgetSnapshot(
            routineName: "Push A", exerciseCount: 5, streakWeeks: 2,
            trainedDays: Array(repeating: false, count: 7), updatedAt: now
        )
        #expect(legacy.entryDates(from: now) == [now])

        // With a plan for tomorrow there is a future entry to hand WidgetKit.
        let planned = snapshot(now: now, plans: ["Push A", "Pull B"]).entryDates(from: now)
        #expect(planned.count == 2)
        #expect(try #require(planned.last) > now)
    }

    @Test("the streak decays once a week with no training rolls past, without the app running")
    func streakDecaysAcrossAWeekBoundary() throws {
        let calendar = Self.calendar()
        // A Monday, so "seven days later" is always a different training week.
        var components = DateComponents(year: 2026, month: 1, day: 5, hour: 10)
        components.calendar = calendar
        let monday = try #require(calendar.date(from: components))
        // Two sessions in the week before: that week counted, so the streak is 1 on Monday.
        let lastWeek = try #require(calendar.date(byAdding: .day, value: -3, to: monday))
        let alsoLastWeek = try #require(calendar.date(byAdding: .day, value: -4, to: monday))
        let snapshot = snapshot(
            now: monday, plans: Array(repeating: nil, count: 8),
            workoutDays: [calendar.startOfDay(for: lastWeek), calendar.startOfDay(for: alsoLastWeek)],
            weeklyGoal: 2
        )

        #expect(snapshot.resolved(on: monday).streakWeeks == 1)
        // A week later, with nothing logged in between, the streak is gone — and nothing had to
        // open the app to work that out.
        let nextMonday = try #require(calendar.date(byAdding: .day, value: 7, to: monday))
        #expect(snapshot.resolved(on: nextMonday).streakWeeks == 0)
    }

    @Test("a timeline with no look-ahead never asks WidgetKit to reload; one with days does")
    func reloadDateOnlyWhenThereIsALookAhead() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let later = now.addingTimeInterval(24 * 60 * 60)

        // `.after(now)` is already in the past when WidgetKit reads it — an immediate reload.
        #expect(WidgetSnapshot.reloadDate(after: [now], now: now) == nil)
        #expect(WidgetSnapshot.reloadDate(after: [], now: now) == nil)
        #expect(WidgetSnapshot.reloadDate(after: [now, later], now: now) == later)
    }

    @Test("before the app has ever run the widget says so instead of claiming a rest day")
    func emptySnapshotAsksToOpenTheApp() throws {
        let resolved = WidgetSnapshot.empty.resolved(on: Date())

        #expect(!resolved.hasData)
        #expect(resolved.routineName == nil)
        #expect(resolved.exerciseCount == 0)
        // The view branches on `hasData`; a written snapshot with no routine is a real rest day.
        let restDay = WidgetSnapshot(
            routineName: nil, exerciseCount: 0, streakWeeks: 0,
            trainedDays: Array(repeating: false, count: 7), updatedAt: Date()
        )
        #expect(restDay.resolved(on: Date()).hasData)
    }
}
