import Foundation
import GymCore
import os

private let snapshotLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "watch-snapshot")

/// What the complications and the Smart Stack card show, written to the App Group by the watch
/// app (`WatchSnapshotWriter`) and read by `DaGymWatchWidgets`. The widget never opens the
/// store. Compiled into both targets.
///
/// Versioned by `version`, under the one `watchSnapshot.v1` key: everything added after the
/// first shape is optional, so an extension a release behind the app (or the other way round —
/// watchOS updates them together, but a decode failure blanks the face) decodes what it knows
/// and ignores the rest. Never rename or retype a field; add a new optional one.
struct WatchSnapshot: Codable, Equatable {
    /// The shape this snapshot was written with — `currentVersion` for anything the app writes
    /// now, nil for a snapshot from before the field existed.
    var version: Int?
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
    /// Version 2: the next planned session with its day label and duration (today's routine
    /// when there is one, else the next scheduled day), for the wrist's Home and the
    /// "Coach says" complication. Duplicates `nextRoutineName`/`nextSessionDate`, which the
    /// original families keep reading.
    var nextSession: NextPlannedSession?
    /// Version 2: the on-device coach's top one-line tip (`CoachGlance.line`), ≤ 60 characters.
    var coachLine: String?

    static let currentVersion = 2

    struct Rest: Codable, Equatable {
        var endDate: Date
        var totalSeconds: Int
        /// "100 × 5" / "Next Bench Press" — already in the lifter's unit.
        var nextLabel: String
        var workoutTitle: String
    }

    static let empty = WatchSnapshot()

    init(
        streakWeeks: Int = 0, nextRoutineName: String? = nil, nextSessionDate: Date? = nil,
        isNextToday: Bool = false
    ) {
        version = Self.currentVersion
        self.streakWeeks = streakWeeks
        self.nextRoutineName = nextRoutineName
        self.nextSessionDate = nextSessionDate
        self.isNextToday = isNextToday
    }

    /// The snapshot as it should read at `now`: a rest that has already ended is dropped (the
    /// app writes `rest: nil` at rest end, but a kill mid-rest leaves the old one behind, and a
    /// countdown to a past date traps `Text(timerInterval:)`), and a "next session" whose day
    /// has passed is cleared rather than left saying "Push A today" all morning.
    func expiring(at now: Date, calendar: Calendar = .current) -> WatchSnapshot {
        var snapshot = self
        if let rest, rest.endDate <= now { snapshot.rest = nil }
        if let date = nextSessionDate, date < calendar.startOfDay(for: now) {
            snapshot.nextRoutineName = nil
            snapshot.nextSessionDate = nil
            snapshot.isNextToday = false
        }
        if let next = nextSession, next.date < calendar.startOfDay(for: now) {
            snapshot.nextSession = nil
        }
        return snapshot
    }
}

enum WatchSnapshotStore {
    static let appGroupID = "group.dev.abdirahmanmohamed.dagym"
    static let key = "watchSnapshot.v1"

    static var appGroupSuite: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func write(_ snapshot: WatchSnapshot, to suite: UserDefaults) {
        do {
            suite.set(try JSONEncoder().encode(snapshot), forKey: key)
        } catch {
            snapshotLogger.error("Snapshot encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The empty snapshot when nothing has been written yet; a decode failure (a Codable drift
    /// between the app and an older extension) is logged so a blank face after an update has
    /// a cause in Console.
    static func read(from suite: UserDefaults) -> WatchSnapshot {
        guard let data = suite.data(forKey: key) else { return .empty }
        do {
            return try JSONDecoder().decode(WatchSnapshot.self, from: data)
        } catch {
            snapshotLogger.error("Snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }
}
