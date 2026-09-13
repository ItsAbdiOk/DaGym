import Foundation
import GymCore
import Testing

@testable import DaGym

@MainActor
@Suite("Preferences persistence")
struct PreferencesTests {
    /// A fresh, isolated `UserDefaults` suite per test, cleaned before use so runs don't
    /// leak into each other (mirrors `ExerciseSeederTests`).
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("every property persists across a fresh Preferences instance on the same suite")
    func persistsAllProperties() throws {
        let suite = makeSuite(#function)
        let first = Preferences(suite: suite)

        first.weightUnit = .lb
        first.effortScale = .rir
        first.defaultRestSeconds = 90
        first.weeklyGoal = 6
        first.keepScreenAwake = false
        first.restSound = false
        first.restHaptics = false
        first.restScreenFlash = true
        first.weekStartsMonday = false
        first.hasCompletedOnboarding = true
        first.trainingGoal = "strength"

        let second = Preferences(suite: suite)
        #expect(second.weightUnit == .lb)
        #expect(second.effortScale == .rir)
        #expect(second.defaultRestSeconds == 90)
        #expect(second.weeklyGoal == 6)
        #expect(second.keepScreenAwake == false)
        #expect(second.restSound == false)
        #expect(second.restHaptics == false)
        #expect(second.restScreenFlash == true)
        #expect(second.weekStartsMonday == false)
        #expect(second.hasCompletedOnboarding == true)
        #expect(second.trainingGoal == "strength")
    }

    @Test("an unseeded suite falls back to the documented defaults")
    func defaultsAreSensible() throws {
        let suite = makeSuite(#function)
        let preferences = Preferences(suite: suite)

        #expect(preferences.weightUnit == .kg)
        #expect(preferences.effortScale == .rpe)
        #expect(preferences.defaultRestSeconds == 150)
        #expect(preferences.weeklyGoal == 4)
        #expect(preferences.keepScreenAwake)
        #expect(preferences.restSound)
        #expect(preferences.restHaptics)
        #expect(!preferences.restScreenFlash)
        #expect(preferences.weekStartsMonday)
        #expect(!preferences.hasCompletedOnboarding)
        #expect(preferences.trainingGoal.isEmpty)
    }

    @Test("formatWeight/unitSymbol follow the selected unit")
    func formattingFollowsUnit() throws {
        let suite = makeSuite(#function)
        let preferences = Preferences(suite: suite)

        preferences.weightUnit = .kg
        #expect(preferences.unitSymbol == "kg")
        #expect(preferences.formatWeight(kg: 82.5) == "82.5")

        preferences.weightUnit = .lb
        #expect(preferences.unitSymbol == "lb")
        #expect(preferences.formatWeight(kg: 100) == WeightUnit.lb.format(kg: 100))
    }
}
