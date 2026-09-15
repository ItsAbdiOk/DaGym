import Foundation
import GymCore

/// The watch's own settings — the four rows on the Settings screen. Stored in the watch's
/// `UserDefaults.standard` under the phone's key names where one exists (`weightUnit`), so the
/// shared `WorkoutStore` reads the same value. The phone's preferences do not sync to the watch
/// in v1: units, haptics and voice are set here, on the wrist.
@MainActor
@Observable
final class WatchPreferences {
    static let shared = WatchPreferences()

    private let defaults: UserDefaults

    /// Weekly goal the streak counts against. Not a Settings row (the phone's `weeklyGoal` does
    /// not sync); the phone's default.
    static let weeklyGoal = 4
    /// The hour a scheduled session defaults to on the complications — the phone's
    /// `scheduledStartHour` default.
    static let scheduledStartHour = 18

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Preferences.Key.weightUnit) }
    }
    var haptics: Bool {
        didSet { defaults.set(haptics, forKey: Key.haptics) }
    }
    var voiceLog: Bool {
        didSet { defaults.set(voiceLog, forKey: Key.voiceLog) }
    }
    /// When the store last saved a finished workout — the "iPhone synced" row's timestamp.
    var lastSavedAt: Date? {
        didSet { defaults.set(lastSavedAt, forKey: Key.lastSavedAt) }
    }

    var distanceUnit: DistanceUnit { DistanceUnit.matching(weightUnit) }

    /// Which day the streak's weeks start on. Not a Settings row (the phone's `weekStartsMonday`
    /// does not sync); the phone's default is Monday and the watch must count the same weeks,
    /// or the two devices quote different streaks. Read under the phone's key so a value that
    /// ever does arrive is honoured. Stored, not derived from the locale: `Calendar.current`
    /// starts on Sunday for a US watch and put Sunday's session in a different week than the
    /// phone did.
    var weekStartsMonday: Bool {
        didSet { defaults.set(weekStartsMonday, forKey: Preferences.Key.weekStartsMonday) }
    }

    /// The calendar every streak, week and "next session" on the wrist is computed with — the
    /// same shape as the phone's `Preferences.trainingCalendar`.
    var trainingCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsMonday ? 2 : 1
        return calendar
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        weightUnit = WeightUnit(rawValue: defaults.string(forKey: Preferences.Key.weightUnit) ?? "") ?? .kg
        haptics = defaults.object(forKey: Key.haptics) as? Bool ?? true
        voiceLog = defaults.object(forKey: Key.voiceLog) as? Bool ?? true
        lastSavedAt = defaults.object(forKey: Key.lastSavedAt) as? Date
        weekStartsMonday = defaults.object(forKey: Preferences.Key.weekStartsMonday) as? Bool ?? true
    }

    private enum Key {
        static let haptics = "watchHaptics"
        static let voiceLog = "watchVoiceLog"
        static let lastSavedAt = "watchLastSavedAt"
    }
}
