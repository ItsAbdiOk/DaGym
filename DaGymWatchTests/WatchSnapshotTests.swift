import Foundation
import Testing

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
}
