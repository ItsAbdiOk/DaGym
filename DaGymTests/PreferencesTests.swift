import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// These used to be 25 `UserDefaults` round-trips, which proved that `didSet` calls `set` and
/// nothing else — every preference in this file was "green" the whole time it silently did
/// nothing. What is asserted now is *behaviour*: flip the preference, run the real code path it
/// claims to govern, and check the answer changed. `HomeSnapshotTests.thisWeekUsesTrainingCalendar`
/// is the pattern.
@MainActor
@Suite("Preferences behaviour")
struct PreferencesTests {
    /// A fresh, isolated `UserDefaults` suite per test, cleaned before use so runs don't
    /// leak into each other (mirrors `ExerciseSeederTests`).
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A two-set session on one exercise whose own rest is `restSeconds` (0 = "unset").
    private func makeSession(restSeconds: Int) -> WorkoutSession {
        let exercise = ExerciseInfo(
            name: "Bench Press", primary: [.chest], equipment: "Barbell", restSeconds: restSeconds
        )
        let sets = [
            SetEntry(kind: .working, weightKg: 80, reps: 8),
            SetEntry(kind: .working, weightKg: 80, reps: 8)
        ]
        return WorkoutSession(
            title: "Push A", subtitle: "", startedAt: Date(),
            exercises: [WorkoutExerciseEntry(exercise: exercise, sets: sets)]
        )
    }

    // MARK: - defaultRestSeconds

    @Test("defaultRestSeconds is the fallback rest for an exercise that carries none of its own")
    func defaultRestFillsInForAnUnsetExercise() throws {
        let session = makeSession(restSeconds: 0)

        session.defaultRestSeconds = 150
        #expect(session.restSeconds(after: 0, set: 0) == 150)

        session.defaultRestSeconds = 45
        #expect(session.restSeconds(after: 0, set: 0) == 45)
    }

    @Test("an exercise starts at 0 = 'use the default', so the setting actually governs it")
    func exercisesFollowTheDefaultUntilOverridden() throws {
        // `ExerciseInfo` (and every custom exercise) carries no rest of its own until the lifter
        // picks one in Exercise Detail; the seeded value used to be 150 everywhere, which made
        // Settings → Default rest and the training goal's 210/90 unreachable decoration.
        let fresh = ExerciseInfo(name: "Bench Press", primary: [.chest], equipment: "Barbell")
        #expect(fresh.restSeconds == 0)
        #expect(fresh.restSeconds(defaultingTo: 210) == 210)

        var pinned = fresh
        pinned.restSeconds = 90
        #expect(pinned.restSeconds(defaultingTo: 210) == 90)
    }

    @Test("Exercise Detail offers a Default choice that stores 0 and names the setting's value")
    func exerciseDetailOffersDefaultRest() throws {
        #expect(ExerciseDetailView.restOptions.first == 0)
        #expect(ExerciseDetailView.restLabel(0, defaultSeconds: 210) == "Default · 3:30")
        #expect(ExerciseDetailView.restLabel(0, defaultSeconds: 0) == "Default · Off")
        #expect(ExerciseDetailView.restLabel(90, defaultSeconds: 210) == "1:30")
    }

    @Test("an exercise with its own rest keeps it; defaultRestSeconds does not override")
    func exerciseRestWinsOverTheDefault() throws {
        let session = makeSession(restSeconds: 90)
        session.defaultRestSeconds = 300

        #expect(session.restSeconds(after: 0, set: 0) == 90)
    }

    @Test("defaultRestSeconds == 0 is Off: no rest starts, even for an exercise with its own rest")
    func offDisablesTheRestTimerEntirely() throws {
        let session = makeSession(restSeconds: 90)
        session.defaultRestSeconds = 0

        #expect(session.restSeconds(after: 0, set: 0) == 0)

        // And completing a set with it off leaves no rest running at all.
        let exerciseID = session.exercises[0].id
        session.completeSet(exerciseID: exerciseID, setID: session.exercises[0].sets[0].id)
        #expect(!session.isResting)
        #expect(session.restEndDate == nil)
    }

    // MARK: - restPauseSeconds

    @Test("restPauseSeconds governs the rest after a rest-pause set")
    func restPauseSecondsIsHonoured() throws {
        let session = makeSession(restSeconds: 120)
        session.exercises[0].sets[0].kind = .restPause

        session.restPauseSeconds = 20
        #expect(session.restSeconds(after: 0, set: 0) == 20)

        session.restPauseSeconds = 35
        #expect(session.restSeconds(after: 0, set: 0) == 35)
    }

    // MARK: - trainingGoal

    @Test("picking a training goal applies that goal's rest length and weekly session count")
    func trainingGoalAppliesItsDefaults() throws {
        let preferences = Preferences(suite: makeSuite(#function))

        preferences.trainingGoal = .strength
        preferences.applyTrainingGoalDefaults()
        #expect(preferences.defaultRestSeconds == Preferences.TrainingGoal.strength.defaultRestSeconds)
        #expect(preferences.weeklyGoal == Preferences.TrainingGoal.strength.weeklyGoal)

        preferences.trainingGoal = .muscle
        preferences.applyTrainingGoalDefaults()
        #expect(preferences.defaultRestSeconds == Preferences.TrainingGoal.muscle.defaultRestSeconds)
        #expect(preferences.weeklyGoal == Preferences.TrainingGoal.muscle.weeklyGoal)

        // The subtitles promise "longer rest" for strength and "shorter rest" for muscle; the
        // numbers behind them have to actually say that.
        #expect(
            Preferences.TrainingGoal.strength.defaultRestSeconds
                > Preferences.TrainingGoal.muscle.defaultRestSeconds
        )
    }

    @Test("the goal survives a relaunch and defaults to general on a fresh install")
    func trainingGoalPersists() throws {
        let suite = makeSuite(#function)
        #expect(Preferences(suite: suite).trainingGoal == .general)

        Preferences(suite: suite).trainingGoal = .strength
        #expect(Preferences(suite: suite).trainingGoal == .strength)
    }

    // MARK: - accent / appearance reach the widget

    @Test("accent and appearance are carried into the widget snapshot, not stopped at the app")
    func themeReachesTheWidgetSnapshot() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))

        preferences.accent = .ice
        preferences.appearance = .light
        let themed = WidgetSnapshotWriter.snapshot(store: store, preferences: preferences)
        #expect(themed.accent == "ice")
        #expect(themed.appearance == "light")

        preferences.accent = .coral
        preferences.appearance = .dark
        let other = WidgetSnapshotWriter.snapshot(store: store, preferences: preferences)
        #expect(other.accent == "coral")
        #expect(other.appearance == "dark")
        // A theme change alone must reach the widget, or the reload is skipped and it stays wrong.
        #expect(!other.sameContent(as: themed))
    }

    // MARK: - weekStartsMonday

    @Test("weekStartsMonday moves the week the widget's streak is computed against")
    func weekStartMovesTheSnapshotWeek() throws {
        let preferences = Preferences(suite: makeSuite(#function))

        preferences.weekStartsMonday = true
        #expect(preferences.trainingCalendar.firstWeekday == 2)

        preferences.weekStartsMonday = false
        #expect(preferences.trainingCalendar.firstWeekday == 1)
    }

    // MARK: - Removed preferences

    /// `syncPhotos` and `deloadDismissedFingerprint` were never read and never written by any UI;
    /// they are gone, and the keys with them. Their absence is asserted by name here so nobody
    /// resurrects a stored value with no consumer.
    @Test("the two dead preference keys are no longer written")
    func deadKeysAreGone() throws {
        let suite = makeSuite(#function)
        let preferences = Preferences(suite: suite)
        preferences.defaultRestSeconds = 60

        #expect(suite.object(forKey: "syncPhotos") == nil)
        #expect(suite.object(forKey: "deloadDismissedFingerprint") == nil)
    }

    // MARK: - Storage still works

    @Test("an unseeded suite falls back to the documented defaults")
    func defaultsAreSensible() throws {
        let preferences = Preferences(suite: makeSuite(#function))

        #expect(preferences.weightUnit == .kg)
        #expect(preferences.effortScale == .rpe)
        #expect(preferences.defaultRestSeconds == 150)
        #expect(preferences.restPauseSeconds == 20)
        #expect(preferences.weeklyGoal == 4)
        #expect(preferences.weekStartsMonday)
        #expect(!preferences.showSetSteppers)
        #expect(!preferences.hasCompletedOnboarding)
        #expect(preferences.trainingGoal == .general)
    }

    @Test("formatWeight/unitSymbol follow the selected unit")
    func formattingFollowsUnit() throws {
        let preferences = Preferences(suite: makeSuite(#function))

        preferences.weightUnit = .kg
        #expect(preferences.unitSymbol == "kg")
        #expect(preferences.formatWeight(kg: 82.5) == "82.5")

        preferences.weightUnit = .lb
        #expect(preferences.unitSymbol == "lb")
        #expect(preferences.formatWeight(kg: 100) == WeightUnit.lb.format(kg: 100))
    }

    @Test("optional properties round-trip nil -> value -> nil, not just value -> value")
    func optionalPropertiesRoundTripThroughNil() throws {
        let suite = makeSuite(#function)
        let first = Preferences(suite: suite)
        #expect(first.bodyweightGoalKg == nil)
        #expect(first.deloadSnoozedUntil == nil)

        first.bodyweightGoalKg = 90
        first.deloadSnoozedUntil = Date(timeIntervalSince1970: 1_700_000_000)

        let second = Preferences(suite: suite)
        #expect(second.bodyweightGoalKg == 90)
        #expect(second.deloadSnoozedUntil == Date(timeIntervalSince1970: 1_700_000_000))

        second.bodyweightGoalKg = nil
        second.deloadSnoozedUntil = nil

        let third = Preferences(suite: suite)
        #expect(third.bodyweightGoalKg == nil)
        #expect(third.deloadSnoozedUntil == nil)
    }
}
