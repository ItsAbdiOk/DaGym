import Foundation

/// What the complications and the Smart Stack card show, written to the App Group by the watch
/// app (`WatchSnapshotWriter`) and read by `DaGymWatchWidgets`. The widget never opens the
/// store. Compiled into both targets.
struct WatchSnapshot: Codable, Equatable {
    /// Consecutive weeks at the weekly goal — the streak the circular complication rings.
    var streakWeeks: Int = 0
    /// Distinct training days this week, for the ring's seven segments.
    var trainedThisWeek: [Bool] = Array(repeating: false, count: 7)
    /// "Push A" and its planned start, for the corner complication and the idle card.
    var nextRoutineName: String?
    var nextSessionDate: Date?
    /// True when today has a routine, so the idle card reads "Push A today".
    var isNextToday = false
    /// Set while a workout is live so every family becomes the rest timer.
    var rest: Rest?

    struct Rest: Codable, Equatable {
        var endDate: Date
        var totalSeconds: Int
        /// "100 × 5" / "Next Bench Press" — already in the lifter's unit.
        var nextLabel: String
        var workoutTitle: String
    }

    static let empty = WatchSnapshot()
}

enum WatchSnapshotStore {
    static let appGroupID = "group.dev.abdirahmanmohamed.dagym"
    static let key = "watchSnapshot.v1"

    static var appGroupSuite: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func write(_ snapshot: WatchSnapshot, to suite: UserDefaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        suite.set(data, forKey: key)
    }

    static func read(from suite: UserDefaults) -> WatchSnapshot {
        guard let data = suite.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
