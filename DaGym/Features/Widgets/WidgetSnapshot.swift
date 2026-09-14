import Foundation

/// What `TodayWorkoutWidget` / `StreakWidget` read. Written by the app (`WidgetSnapshotWriter`)
/// after every finish/schedule change; the widgets never open the SwiftData store themselves.
/// Shared verbatim between the `DaGym` and `DaGymWidgets` targets (see `project.yml`) — keep it
/// additive so an old widget binary can still decode a newer app's snapshot.
struct WidgetSnapshot: Codable, Equatable {
    var routineName: String?
    var exerciseCount: Int
    var streakWeeks: Int
    /// The last 7 calendar days, oldest first. `true` means a workout was finished that day.
    var trainedDays: [Bool]
    var updatedAt: Date
    /// Today's routine's glyph (SF Symbol name + `RoutineTint` raw value — see `RoutineGlyph` in
    /// the app target, which this widget can't import). Optional so a snapshot written by an
    /// older app build still decodes here, and nil on a rest day (no `routineName` either).
    var routineSymbolName: String?
    var routineTint: String?

    static let empty = WidgetSnapshot(
        routineName: nil, exerciseCount: 0, streakWeeks: 0,
        trainedDays: Array(repeating: false, count: 7), updatedAt: .distantPast
    )
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
