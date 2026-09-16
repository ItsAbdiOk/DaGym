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
    /// The suite every property persists to. Internal (not private) for the one-shot device
    /// markers in `Preferences+Storage.swift`, which read and write it directly instead of
    /// adding stored, observed properties to a class already at the type-body cap.
    let defaults: UserDefaults

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) }
    }
    /// The unit cardio distances are shown in; storage stays metres. Decided once, on first
    /// read, from the weight unit (lb lifters get miles) and written straight back so a later
    /// change of weight unit never silently flips it — Settings › Units changes it explicitly.
    var distanceUnit: DistanceUnit {
        didSet { defaults.set(distanceUnit.rawValue, forKey: Key.distanceUnit) }
    }
    var effortScale: Effort.Scale {
        didSet { defaults.set(effortScale.rawValue, forKey: Key.effortScale) }
    }
    /// The fallback rest used whenever an exercise carries no rest of its own, and the master
    /// switch for the rest timer: `0` ("Off" in Settings) means no rest timer ever starts, for
    /// any exercise. Honoured by `WorkoutSession.restSeconds(after:set:)` — the one place every
    /// real rest comes from — and by the Control Center "Rest timer" intent.
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
    /// The training goal picked on onboarding's Goal step and editable in Settings. Read by
    /// `applyTrainingGoalDefaults()`, which is what makes the answer matter: each goal carries
    /// the rest length and weekly session count its own subtitle promises.
    var trainingGoal: TrainingGoal {
        didSet { defaults.set(trainingGoal.rawValue, forKey: Key.trainingGoal) }
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

    /// The accent theme (plan.md Phase 8). Defaults to the shipped brand colour, `.coral`.
    /// `DGColor.coral`/`coralText` resolve from `DGColor.current`, which this keeps in sync so
    /// every existing call site re-themes without being touched — see `DGColor.swift`.
    var accent: DGAccent {
        didSet {
            defaults.set(accent.rawValue, forKey: Key.accent)
            DGColor.current = accent
        }
    }

    /// "Colour-blind-friendly heatmaps" in Settings › Display: forces the recovery map and
    /// consistency calendar onto `DGColor.recoveryAccessible`/`consistencyAccessible` even when
    /// the system-wide "Differentiate Without Color" setting is off. Off by default — that
    /// system setting already forces the accessible ramp regardless of this toggle, so this only
    /// matters to someone who wants the safer ramp without changing an OS-wide setting that
    /// affects every other app too.
    var colorBlindHeatmaps: Bool {
        didSet { defaults.set(colorBlindHeatmaps, forKey: Key.colorBlindHeatmaps) }
    }

    /// The saved active-workout layout (OpenGym parity 1): Cards, List or Compact. Set in
    /// Settings › Workout; the active screen's "…" menu overrides it for one session without
    /// writing here. Migrates the older "Compact layout" toggle on first read.
    var workoutLayout: WorkoutLayout {
        didSet { defaults.set(workoutLayout.rawValue, forKey: Key.workoutLayout) }
    }
    /// ± buttons around weight/reps on a set row, stepping by the exercise increment. Toggled
    /// from the active workout's "…" menu and Settings › Workout.
    var showSetSteppers: Bool {
        didSet { defaults.set(showSetSteppers, forKey: Key.showSetSteppers) }
    }
    /// The short rest a rest-pause burst starts instead of the exercise's full rest. Set from
    /// Settings' Rest Timer card.
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
    /// Lets the coach use Apple's on-device language model (Foundation Models) where the system
    /// says it's available. On by default: it runs entirely on the phone and nothing leaves it.
    /// Off, every coach feature falls back to `RuleCoachModel` — same cards, rule wording.
    var onDeviceCoachEnabled: Bool {
        didSet { defaults.set(onDeviceCoachEnabled, forKey: Key.onDeviceCoachEnabled) }
    }
    /// The OpenRouter model the cloud coach talks to, by its OpenRouter id. The key itself is
    /// in the Keychain (`CoachChatSettings`), never here.
    var coachModelID: String {
        didSet { defaults.set(coachModelID, forKey: Key.coachModelID) }
    }
    /// The second-opinion model every proposal is sent to, by OpenRouter id; nil turns the
    /// second opinion off. Stored as `Key.coachReviewerModelID` with "" meaning off, so "never
    /// set" (default on) and "turned off" are told apart.
    var coachReviewerModelID: String? {
        didSet { defaults.set(coachReviewerModelID ?? "", forKey: Key.coachReviewerModelID) }
    }
    /// The lifter agreed that their training data is sent to OpenRouter and the chosen model.
    /// Shown once when a key is first saved; nothing is sent until this is true.
    var coachChatConsentGiven: Bool {
        didSet { defaults.set(coachChatConsentGiven, forKey: Key.coachChatConsentGiven) }
    }
    /// `CoachWeekReview.weekKey` of the last Sunday check-in started, and of the one the
    /// lifter dismissed with "Not this week". Home's card hides for a week named in either.
    var coachWeekReviewLastKey: String? {
        didSet { defaults.set(coachWeekReviewLastKey, forKey: Key.coachWeekReviewLastKey) }
    }
    var coachWeekReviewDismissedKey: String? {
        didSet { defaults.set(coachWeekReviewDismissedKey, forKey: Key.coachWeekReviewDismissedKey) }
    }

    init(suite: UserDefaults = .standard) {
        defaults = suite
        workoutLayout = Self.workoutLayoutValue(suite)
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
        onDeviceCoachEnabled = Self.boolValue(suite, Key.onDeviceCoachEnabled, default: true)
        coachModelID = suite.string(forKey: Key.coachModelID) ?? CoachChatConfiguration.defaultModelID
        coachReviewerModelID = Self.reviewerModelID(suite.string(forKey: Key.coachReviewerModelID))
        coachChatConsentGiven = Self.boolValue(suite, Key.coachChatConsentGiven, default: false)
        coachWeekReviewLastKey = suite.string(forKey: Key.coachWeekReviewLastKey)
        coachWeekReviewDismissedKey = suite.string(forKey: Key.coachWeekReviewDismissedKey)
        let unit = WeightUnit(rawValue: suite.string(forKey: Key.weightUnit) ?? "") ?? .kg
        weightUnit = unit
        if let stored = DistanceUnit(rawValue: suite.string(forKey: Key.distanceUnit) ?? "") {
            distanceUnit = stored
        } else {
            let derived = DistanceUnit.matching(unit)
            distanceUnit = derived
            suite.set(derived.rawValue, forKey: Key.distanceUnit)
        }
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
        lockPhotos = Self.boolValue(suite, Key.lockPhotos, default: false)
        hasCompletedOnboarding = Self.boolValue(suite, Key.hasCompletedOnboarding, default: false)
        trainingGoal = TrainingGoal(rawValue: suite.string(forKey: Key.trainingGoal) ?? "") ?? .general
        deloadSnoozedUntil = suite.object(forKey: Key.deloadSnoozedUntil) as? Date
        accent = DGAccent(rawValue: suite.string(forKey: Key.accent) ?? "") ?? .coral
        colorBlindHeatmaps = Self.boolValue(suite, Key.colorBlindHeatmaps, default: false)
        DGColor.current = accent
    }

    /// Writes the current goal's training defaults into the preferences it implies. Called when
    /// the goal is picked (onboarding) or changed (Settings) — never on launch, so a lifter who
    /// later tunes rest or weekly goal by hand keeps their own numbers.
    func applyTrainingGoalDefaults() {
        defaultRestSeconds = trainingGoal.defaultRestSeconds
        weeklyGoal = trainingGoal.weeklyGoal
    }

    /// A canonical kg value, formatted and rounded for the user's unit.
    func formatWeight(kg: Double) -> String { weightUnit.format(kg: kg) }

    /// A canonical metres value in the user's distance unit, with its symbol: "5.00 km".
    func formatDistance(meters: Double, decimals: Int = 2) -> String {
        distanceUnit.formatWithSymbol(meters: meters, decimals: decimals)
    }

    var unitSymbol: String { weightUnit.symbol }

    /// A large kg total (session/lifetime volume), converted to the user's
    /// unit and grouped with a thin-space thousands separator.
    func formatVolume(kg: Double) -> String {
        let display = weightUnit.display(kg: kg)
        return Self.volumeFormatter.string(from: NSNumber(value: display)) ?? "\(Int(display))"
    }

    /// Shared by every volume label on screen; History rows, tiles and recap cards all call
    /// `formatVolume` per render, and a `NumberFormatter` costs far more than the string.
    private static let volumeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

}
