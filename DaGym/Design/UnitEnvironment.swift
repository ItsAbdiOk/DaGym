import Foundation
import GymCore

/// User preferences: unit, effort scale, rest defaults and small display
/// toggles. Persisted to `UserDefaults` and shared through the environment
/// (`@Environment(Preferences.self)`). Weights stay canonical kg everywhere
/// else (plan.md §3) — this type is only where the display unit lives.
@Observable
@MainActor
final class Preferences {
    private enum Key {
        static let weightUnit = "weightUnit"
        static let effortScale = "effortScale"
        static let defaultRestSeconds = "defaultRestSeconds"
        static let weeklyGoal = "weeklyGoal"
        static let keepScreenAwake = "keepScreenAwake"
        static let restSound = "restSound"
        static let restHaptics = "restHaptics"
        static let restScreenFlash = "restScreenFlash"
        static let weekStartsMonday = "weekStartsMonday"
        static let healthWriteWorkouts = "healthWriteWorkouts"
        static let healthSyncBodyweight = "healthSyncBodyweight"
        static let healthReadRecovery = "healthReadRecovery"
        static let calendarSyncEnabled = "calendarSyncEnabled"
        static let scheduledStartHour = "scheduledStartHour"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
    }

    private let defaults: UserDefaults

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) }
    }
    var effortScale: Effort.Scale {
        didSet { defaults.set(effortScale.rawValue, forKey: Key.effortScale) }
    }
    var defaultRestSeconds: Int {
        didSet { defaults.set(defaultRestSeconds, forKey: Key.defaultRestSeconds) }
    }
    var weeklyGoal: Int {
        didSet { defaults.set(weeklyGoal, forKey: Key.weeklyGoal) }
    }
    var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake) }
    }
    var restSound: Bool {
        didSet { defaults.set(restSound, forKey: Key.restSound) }
    }
    var restHaptics: Bool {
        didSet { defaults.set(restHaptics, forKey: Key.restHaptics) }
    }
    var restScreenFlash: Bool {
        didSet { defaults.set(restScreenFlash, forKey: Key.restScreenFlash) }
    }
    var weekStartsMonday: Bool {
        didSet { defaults.set(weekStartsMonday, forKey: Key.weekStartsMonday) }
    }
    /// Writes every finished workout to Apple Health as an `HKWorkout`. Off until the user turns
    /// it on in the Apple Health settings screen (plan.md §6.8).
    var healthWriteWorkouts: Bool {
        didSet { defaults.set(healthWriteWorkouts, forKey: Key.healthWriteWorkouts) }
    }
    /// Two-way bodyweight sync with Apple Health (Health is the source of truth when this is on).
    var healthSyncBodyweight: Bool {
        didSet { defaults.set(healthSyncBodyweight, forKey: Key.healthSyncBodyweight) }
    }
    /// Reads HRV, resting heart rate and sleep for recovery-aware coaching (P6). Read-only —
    /// never written.
    var healthReadRecovery: Bool {
        didSet { defaults.set(healthReadRecovery, forKey: Key.healthReadRecovery) }
    }
    /// Mirrors the weekly schedule onto a dedicated "DaGym" calendar via EventKit (plan.md §6.8).
    var calendarSyncEnabled: Bool {
        didSet { defaults.set(calendarSyncEnabled, forKey: Key.calendarSyncEnabled) }
    }
    /// Local hour (0–23) planned sessions without a specific time default to.
    var scheduledStartHour: Int {
        didSet { defaults.set(scheduledStartHour, forKey: Key.scheduledStartHour) }
    }
    /// SwiftData + CloudKit private-database sync (plan.md §6.3). Default on: most people expect
    /// their data to follow them across devices. Read by `ModelContainer.dagym(...)` — changing
    /// it applies on next launch, since the store's CloudKit configuration is fixed at open time.
    var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Key.iCloudSyncEnabled) }
    }

    init(suite: UserDefaults = .standard) {
        defaults = suite
        weightUnit = WeightUnit(rawValue: suite.string(forKey: Key.weightUnit) ?? "") ?? .kg
        effortScale = Effort.Scale(rawValue: suite.string(forKey: Key.effortScale) ?? "") ?? .rpe
        defaultRestSeconds = Self.intValue(suite, Key.defaultRestSeconds, default: 150)
        weeklyGoal = Self.intValue(suite, Key.weeklyGoal, default: 4)
        keepScreenAwake = Self.boolValue(suite, Key.keepScreenAwake, default: true)
        restSound = Self.boolValue(suite, Key.restSound, default: true)
        restHaptics = Self.boolValue(suite, Key.restHaptics, default: true)
        restScreenFlash = Self.boolValue(suite, Key.restScreenFlash, default: false)
        weekStartsMonday = Self.boolValue(suite, Key.weekStartsMonday, default: true)
        healthWriteWorkouts = Self.boolValue(suite, Key.healthWriteWorkouts, default: false)
        healthSyncBodyweight = Self.boolValue(suite, Key.healthSyncBodyweight, default: false)
        healthReadRecovery = Self.boolValue(suite, Key.healthReadRecovery, default: false)
        calendarSyncEnabled = Self.boolValue(suite, Key.calendarSyncEnabled, default: false)
        scheduledStartHour = Self.intValue(suite, Key.scheduledStartHour, default: 18)
        iCloudSyncEnabled = Self.boolValue(suite, Key.iCloudSyncEnabled, default: true)
    }

    /// A canonical kg value, formatted and rounded for the user's unit.
    func formatWeight(kg: Double) -> String { weightUnit.format(kg: kg) }

    var unitSymbol: String { weightUnit.symbol }

    /// A large kg total (session/lifetime volume), converted to the user's
    /// unit and grouped with a thin-space thousands separator.
    func formatVolume(kg: Double) -> String {
        let display = weightUnit.display(kg: kg)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: display)) ?? "\(Int(display))"
    }

    private static func intValue(_ suite: UserDefaults, _ key: String, default value: Int) -> Int {
        suite.object(forKey: key) as? Int ?? value
    }

    private static func boolValue(_ suite: UserDefaults, _ key: String, default value: Bool) -> Bool {
        suite.object(forKey: key) as? Bool ?? value
    }
}
