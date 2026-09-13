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
        static let streakRemindersEnabled = "streakRemindersEnabled"
        static let weeklyRecapEnabled = "weeklyRecapEnabled"
        static let reminderHour = "reminderHour"
        static let bodyweightGoalKg = "bodyweightGoalKg"
        static let syncPhotos = "syncPhotos"
        static let lockPhotos = "lockPhotos"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let trainingGoal = "trainingGoal"
        static let deloadSnoozedUntil = "deloadSnoozedUntil"
        static let deloadDismissedFingerprint = "deloadDismissedFingerprint"
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
    /// The Saturday-evening "goal at risk" notification (plan.md §6.4). On by default.
    var streakRemindersEnabled: Bool {
        didSet { defaults.set(streakRemindersEnabled, forKey: Key.streakRemindersEnabled) }
    }
    /// The Sunday 18:00 weekly-recap notification. On by default.
    var weeklyRecapEnabled: Bool {
        didSet { defaults.set(weeklyRecapEnabled, forKey: Key.weeklyRecapEnabled) }
    }
    /// Local hour (0–23) both training reminders fire at.
    var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: Key.reminderHour) }
    }
    /// The bodyweight goal line on the Body screen's chart (plan.md §6.4). Nil until the user
    /// sets one — no goal is assumed.
    var bodyweightGoalKg: Double? {
        didSet {
            if let bodyweightGoalKg {
                defaults.set(bodyweightGoalKg, forKey: Key.bodyweightGoalKg)
            } else {
                defaults.removeObject(forKey: Key.bodyweightGoalKg)
            }
        }
    }

    /// Whether progress photos should sync through iCloud (plan.md §6.4 "don't sync photos").
    /// Off by default — photos are the most sensitive thing in the app, so they stay local unless
    /// the user opts in. Read by `ModelContainer.dagym(...)`'s caller when choosing whether to
    /// point the photo store's CloudKit database at anything (currently always `.none`; wiring
    /// this preference through to the container is future work — see `WorkoutStore+Photos.swift`).
    var syncPhotos: Bool {
        didSet { defaults.set(syncPhotos, forKey: Key.syncPhotos) }
    }
    /// Face ID gate in front of the progress-photos grid (`PhotoLockGate`). Off by default.
    var lockPhotos: Bool {
        didSet { defaults.set(lockPhotos, forKey: Key.lockPhotos) }
    }
    /// Whether `OnboardingFlow` has been completed (or skipped through to the end) at least
    /// once. Gates `AppRootContainer`'s choice between `OnboardingFlow` and `RootView` (plan
    /// §6.9). Off until onboarding finishes so a killed app resumes onboarding, not the tab bar.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }
    /// The training goal picked on the onboarding Goal step: "strength", "muscle" or "general".
    /// Empty until the user picks one (onboarding always sets it before finishing).
    var trainingGoal: String {
        didSet { defaults.set(trainingGoal, forKey: Key.trainingGoal) }
    }
    /// Home's "why a deload?" card hides itself until this date (plan.md §6.5's "Not now",
    /// a 7-day snooze). Nil means never snoozed.
    var deloadSnoozedUntil: Date? {
        didSet {
            if let deloadSnoozedUntil {
                defaults.set(deloadSnoozedUntil, forKey: Key.deloadSnoozedUntil)
            } else {
                defaults.removeObject(forKey: Key.deloadSnoozedUntil)
            }
        }
    }

    /// The evidence fingerprint (`GymCore.DeloadSuggestion.fingerprint`) of the last deload
    /// suggestion the user dismissed with "Not now" — suppresses that exact evidence from
    /// reappearing while still surfacing a newer reason (plan.md §6.5, A4c).
    var deloadDismissedFingerprint: String? {
        didSet {
            if let deloadDismissedFingerprint {
                defaults.set(deloadDismissedFingerprint, forKey: Key.deloadDismissedFingerprint)
            } else {
                defaults.removeObject(forKey: Key.deloadDismissedFingerprint)
            }
        }
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
        streakRemindersEnabled = Self.boolValue(suite, Key.streakRemindersEnabled, default: true)
        weeklyRecapEnabled = Self.boolValue(suite, Key.weeklyRecapEnabled, default: true)
        reminderHour = Self.intValue(suite, Key.reminderHour, default: 18)
        bodyweightGoalKg = suite.object(forKey: Key.bodyweightGoalKg) as? Double
        syncPhotos = Self.boolValue(suite, Key.syncPhotos, default: false)
        lockPhotos = Self.boolValue(suite, Key.lockPhotos, default: false)
        hasCompletedOnboarding = Self.boolValue(suite, Key.hasCompletedOnboarding, default: false)
        trainingGoal = suite.string(forKey: Key.trainingGoal) ?? ""
        deloadSnoozedUntil = suite.object(forKey: Key.deloadSnoozedUntil) as? Date
        deloadDismissedFingerprint = suite.string(forKey: Key.deloadDismissedFingerprint)
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
