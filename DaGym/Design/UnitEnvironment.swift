import Foundation
import GymCore
import SwiftUI

/// User preferences: unit, effort scale, rest defaults and small display
/// toggles. Persisted to `UserDefaults` and shared through the environment
/// (`@Environment(Preferences.self)`). Weights stay canonical kg everywhere
/// else (plan.md §3) — this type is only where the display unit lives.
@Observable
@MainActor
final class Preferences {
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
    /// The single definition of "this week" for the whole app — every weekly computation
    /// (streak, milestone, consistency heat-map, History's "This Week" bucket, the goal-at-risk
    /// and weekly-recap notifications, the Progress charts) must read `firstWeekday` from this
    /// calendar instead of `Calendar.current`, so a Sunday session lands in the same week on
    /// every screen regardless of device locale.
    var trainingCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartsMonday ? 2 : 1
        return calendar
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
    /// Reads body fat %, lean body mass and height from Health to fill in Body screen fields
    /// that would otherwise need a manual entry. Read-only — never written.
    var healthReadBodyComposition: Bool {
        didSet { defaults.set(healthReadBodyComposition, forKey: Key.healthReadBodyComposition) }
    }
    /// Imports `HKWorkout` strength sessions logged in other apps (or a Watch) into History.
    /// Deduplicated hard: `HealthSyncService.pullExternalWorkouts` never imports a workout DaGym
    /// itself wrote, and never imports the same external workout twice (plan.md §6.8).
    var healthImportWorkouts: Bool {
        didSet { defaults.set(healthImportWorkouts, forKey: Key.healthImportWorkouts) }
    }
    /// Off by default, and only meaningful with `healthImportWorkouts` on: lets the HealthKit
    /// background observer import new external sessions on its own. Without it, importing only
    /// ever happens on the explicit Import tap — which is what the settings copy promises, and
    /// what stops a workout appearing in History behind the user's back.
    var healthAutoImportWorkouts: Bool {
        didSet { defaults.set(healthAutoImportWorkouts, forKey: Key.healthAutoImportWorkouts) }
    }
    /// Off by default: writes a rough, clearly-flagged active-energy estimate to Health with each
    /// finished workout, because the phone alone has no heart-rate data to back a real number
    /// (see the comment on `HealthKitStore.saveWorkout`). Never on unless the user opts in.
    var healthEstimateCalories: Bool {
        didSet { defaults.set(healthEstimateCalories, forKey: Key.healthEstimateCalories) }
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
    /// The Saturday-evening "goal at risk" notification (plan.md §6.4). Off by default — see
    /// S13(a): the onboarding step promises no nagging until the user opts in.
    var streakRemindersEnabled: Bool {
        didSet { defaults.set(streakRemindersEnabled, forKey: Key.streakRemindersEnabled) }
    }
    /// The Sunday 18:00 weekly-recap notification. Off by default (S13(a)), same reasoning as
    /// `streakRemindersEnabled`.
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

    /// The accent theme (plan.md Phase 8). Defaults to the shipped brand colour, `.coral`.
    /// `DGColor.coral`/`coralText` resolve from `DGColor.current`, which this keeps in sync so
    /// every existing call site re-themes without being touched — see `DGColor.swift`.
    var accent: DGAccent {
        didSet {
            defaults.set(accent.rawValue, forKey: Key.accent)
            DGColor.current = accent
        }
    }

    /// Active workout: hide the last-3 strip, chips and plate line (OpenGym parity, features 24).
    var compactWorkoutLayout: Bool {
        didSet { defaults.set(compactWorkoutLayout, forKey: Key.compactWorkoutLayout) }
    }
    /// ± buttons around weight/reps on a set row, stepping by the exercise increment.
    var showSetSteppers: Bool {
        didSet { defaults.set(showSetSteppers, forKey: Key.showSetSteppers) }
    }
    /// The short rest a rest-pause burst starts instead of the exercise's full rest.
    var restPauseSeconds: Int {
        didSet { defaults.set(restPauseSeconds, forKey: Key.restPauseSeconds) }
    }
    /// "Workout day" reminder on each scheduled day at `workoutDayReminderHour`. Off by default,
    /// same no-nagging promise as the streak reminder.
    var workoutDayReminderEnabled: Bool {
        didSet { defaults.set(workoutDayReminderEnabled, forKey: Key.workoutDayReminderEnabled) }
    }
    var workoutDayReminderHour: Int {
        didSet { defaults.set(workoutDayReminderHour, forKey: Key.workoutDayReminderHour) }
    }
    /// False hides the effort (RPE/RIR) column everywhere; the engine treats unrated sets as
    /// "no effort data", never as RPE 10.
    var effortTrackingEnabled: Bool {
        didSet { defaults.set(effortTrackingEnabled, forKey: Key.effortTrackingEnabled) }
    }
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    var bodyFigure: BodyFigure {
        didSet { defaults.set(bodyFigure.rawValue, forKey: Key.bodyFigure) }
    }
    /// Rest-end sound plays through the playback session even with the ringer switch on silent
    /// (it pauses other audio, so it's opt-in).
    var playRestSoundOnSilent: Bool {
        didSet { defaults.set(playRestSoundOnSilent, forKey: Key.playRestSoundOnSilent) }
    }
    /// Show the bodyweight sheet before every workout starts (skippable).
    var weighInBeforeWorkout: Bool {
        didSet { defaults.set(weighInBeforeWorkout, forKey: Key.weighInBeforeWorkout) }
    }
    /// The store is filled with sample data the user chose to explore; a banner offers one-tap wipe.
    var sampleDataMode: Bool {
        didSet { defaults.set(sampleDataMode, forKey: Key.sampleDataMode) }
    }
    /// Voice logging speaks a short confirmation ("eight reps at 225 logged") back via
    /// `AVSpeechSynthesis` when audio is routed to headphones — silent on the phone speaker
    /// either way, so this only matters mid-workout with AirPods in. On by default: it's the
    /// whole point of hands-free logging, but off is one tap away for anyone who'd rather glance
    /// at the "what I understood" confirmation instead.
    var voiceSpeakBackOnHeadphones: Bool {
        didSet { defaults.set(voiceSpeakBackOnHeadphones, forKey: Key.voiceSpeakBackOnHeadphones) }
    }
    /// Lets a voice command write a set straight into the workout, with no confirmation card —
    /// only when `VoiceAutoLogPolicy`'s gate clears (a final recognition hypothesis whose own
    /// confidence *and* the parser's both reach 0.90, a single set, no validator warning).
    ///
    /// **Off by default, deliberately.** Auto-log is the one path in the app that mutates
    /// training history without the user seeing what's about to be written, so it stays opt-in
    /// until the gate has proved itself on real utterances. With it off, every command lands on
    /// the review card first — which costs one tap and can't quietly log the wrong number.
    var voiceAutoLogEnabled: Bool {
        didSet { defaults.set(voiceAutoLogEnabled, forKey: Key.voiceAutoLogEnabled) }
    }

    enum Appearance: String, CaseIterable, Codable {
        case system, light, dark
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum BodyFigure: String, CaseIterable, Codable {
        case neutral, male, female
    }

    init(suite: UserDefaults = .standard) {
        defaults = suite
        compactWorkoutLayout = Self.boolValue(suite, Key.compactWorkoutLayout, default: false)
        showSetSteppers = Self.boolValue(suite, Key.showSetSteppers, default: false)
        restPauseSeconds = Self.intValue(suite, Key.restPauseSeconds, default: 20)
        workoutDayReminderEnabled = Self.boolValue(suite, Key.workoutDayReminderEnabled, default: false)
        workoutDayReminderHour = Self.intValue(suite, Key.workoutDayReminderHour, default: 8)
        effortTrackingEnabled = Self.boolValue(suite, Key.effortTrackingEnabled, default: true)
        appearance = Appearance(rawValue: suite.string(forKey: Key.appearance) ?? "") ?? .system
        bodyFigure = BodyFigure(rawValue: suite.string(forKey: Key.bodyFigure) ?? "") ?? .neutral
        playRestSoundOnSilent = Self.boolValue(suite, Key.playRestSoundOnSilent, default: false)
        weighInBeforeWorkout = Self.boolValue(suite, Key.weighInBeforeWorkout, default: false)
        sampleDataMode = Self.boolValue(suite, Key.sampleDataMode, default: false)
        voiceSpeakBackOnHeadphones = Self.boolValue(suite, Key.voiceSpeakBackOnHeadphones, default: true)
        voiceAutoLogEnabled = Self.boolValue(suite, Key.voiceAutoLogEnabled, default: false)
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
        healthReadBodyComposition = Self.boolValue(suite, Key.healthReadBodyComposition, default: false)
        healthImportWorkouts = Self.boolValue(suite, Key.healthImportWorkouts, default: false)
        healthAutoImportWorkouts = Self.boolValue(
            suite, Key.healthAutoImportWorkouts, default: false
        )
        healthEstimateCalories = Self.boolValue(suite, Key.healthEstimateCalories, default: false)
        calendarSyncEnabled = Self.boolValue(suite, Key.calendarSyncEnabled, default: false)
        scheduledStartHour = Self.intValue(suite, Key.scheduledStartHour, default: 18)
        iCloudSyncEnabled = Self.boolValue(suite, Key.iCloudSyncEnabled, default: true)
        // S13(a): the onboarding notifications step promises "Rest timer only, never nagging" —
        // defaulting these two weekly nudges on would send them the moment permission is
        // granted, before the user ever visits Settings to opt in.
        streakRemindersEnabled = Self.boolValue(suite, Key.streakRemindersEnabled, default: false)
        weeklyRecapEnabled = Self.boolValue(suite, Key.weeklyRecapEnabled, default: false)
        reminderHour = Self.intValue(suite, Key.reminderHour, default: 18)
        bodyweightGoalKg = suite.object(forKey: Key.bodyweightGoalKg) as? Double
        syncPhotos = Self.boolValue(suite, Key.syncPhotos, default: false)
        lockPhotos = Self.boolValue(suite, Key.lockPhotos, default: false)
        hasCompletedOnboarding = Self.boolValue(suite, Key.hasCompletedOnboarding, default: false)
        trainingGoal = suite.string(forKey: Key.trainingGoal) ?? ""
        deloadSnoozedUntil = suite.object(forKey: Key.deloadSnoozedUntil) as? Date
        deloadDismissedFingerprint = suite.string(forKey: Key.deloadDismissedFingerprint)
        accent = DGAccent(rawValue: suite.string(forKey: Key.accent) ?? "") ?? .coral
        DGColor.current = accent
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

}
