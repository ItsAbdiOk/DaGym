import Foundation
import Testing
import WidgetKit

@testable import DaGymWatch

@Suite("WatchSnapshot encode/decode")
struct WatchSnapshotTests {
    @Test("a full snapshot round-trips through the App Group store")
    func roundTrip() {
        let suite = WatchTestDefaults.fresh()
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = WatchSnapshot(streakWeeks: 12, nextRoutineName: "Push A", nextSessionDate: end)
        snapshot.trainedThisWeek = [true, false, true, false, false, false, false]
        snapshot.isNextToday = true
        snapshot.rest = WatchSnapshot.Rest(
            endDate: end, totalSeconds: 150, nextLabel: "100 × 5", workoutTitle: "Push A"
        )

        WatchSnapshotStore.write(snapshot, to: suite)

        #expect(WatchSnapshotStore.read(from: suite) == snapshot)
    }

    @Test("an empty or corrupt suite reads as the empty snapshot")
    func emptyAndCorrupt() {
        let suite = WatchTestDefaults.fresh()
        #expect(WatchSnapshotStore.read(from: suite) == .empty)

        suite.set(Data("not json".utf8), forKey: WatchSnapshotStore.key)
        #expect(WatchSnapshotStore.read(from: suite) == .empty)
    }

    @Test("the empty snapshot has seven untrained days and no rest")
    func emptyShape() {
        #expect(WatchSnapshot.empty.trainedThisWeek.count == 7)
        #expect(!WatchSnapshot.empty.trainedThisWeek.contains(true))
        #expect(WatchSnapshot.empty.rest == nil)
        #expect(WatchSnapshot.empty.streakWeeks == 0)
    }

    @Test("trainedDays marks this week's training days by weekday, first weekday first")
    @MainActor
    func trainedDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        // Wednesday 2026-09-16.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 10)))
        let monday = try #require(calendar.date(byAdding: .day, value: -2, to: now))
        let lastWeek = try #require(calendar.date(byAdding: .day, value: -8, to: now))

        let days = WatchSnapshotWriter.trainedDays([monday, now, lastWeek], calendar: calendar, now: now)

        #expect(days == [true, false, true, false, false, false, false])
    }

    @Test("a rest already past and a next session whose day has gone are dropped at read time")
    func expiring() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 22)))
        var snapshot = WatchSnapshot(streakWeeks: 3, nextRoutineName: "Push A", isNextToday: true)
        snapshot.nextSessionDate = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
        snapshot.rest = WatchSnapshot.Rest(
            endDate: now.addingTimeInterval(-1), totalSeconds: 90, nextLabel: "n", workoutTitle: "t"
        )

        // Still today: the rest is stale (a kill mid-rest left it behind), the session is not.
        let tonight = snapshot.expiring(at: now, calendar: calendar)
        #expect(tonight.rest == nil)
        #expect(tonight.nextRoutineName == "Push A")
        #expect(tonight.isNextToday)

        // After midnight "Push A today" is yesterday's news; the streak stays.
        let midnight = calendar.startOfDay(for: now)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
        let morning = snapshot.expiring(at: tomorrow, calendar: calendar)
        #expect(morning.nextRoutineName == nil)
        #expect(morning.nextSessionDate == nil)
        #expect(!morning.isNextToday)
        #expect(morning.streakWeeks == 3)

        // A session on a later day survives the midnight pass.
        var later = snapshot
        later.rest = nil
        later.isNextToday = false
        later.nextSessionDate = calendar.date(byAdding: .day, value: 2, to: now)
        #expect(later.expiring(at: tomorrow, calendar: calendar).nextRoutineName == "Push A")
    }

    @Test("the timeline hands a rest back to idle at its end, and clears today's session at midnight")
    func timelineEntries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 10)))
        var idle = WatchSnapshot(streakWeeks: 3, nextRoutineName: "Push A", isNextToday: true)
        idle.nextSessionDate = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
        let midnight = calendar.startOfDay(for: now)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))

        let idleTimeline = WatchSnapshotEntry.timeline(for: idle, now: now, calendar: calendar)
        #expect(idleTimeline.entries.map(\.date) == [now, tomorrow])
        #expect(idleTimeline.entries.last?.snapshot.nextRoutineName == nil)
        #expect(idleTimeline.entries.last?.snapshot.streakWeeks == 3)

        var resting = idle
        let end = now.addingTimeInterval(90)
        resting.rest = WatchSnapshot.Rest(endDate: end, totalSeconds: 90, nextLabel: "n", workoutTitle: "t")
        let restTimeline = WatchSnapshotEntry.timeline(for: resting, now: now, calendar: calendar)
        #expect(restTimeline.entries.map(\.date) == [now, end])
        #expect(restTimeline.entries.first?.snapshot.rest != nil)
        #expect(restTimeline.entries.last?.snapshot.rest == nil)

        // Nothing planned and no rest: one entry, nothing to expire.
        let empty = WatchSnapshotEntry.timeline(for: .empty, now: now, calendar: calendar)
        #expect(empty.entries.count == 1)
    }
}
