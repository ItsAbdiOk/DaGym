import Foundation
import GymCore
import Testing

@testable import DaGymWatch

@Suite("WatchPreferences round-trip")
@MainActor
struct WatchPreferencesTests {
    @Test("defaults are kg, haptics on, voice on, never saved")
    func defaults() {
        let preferences = WatchPreferences(defaults: WatchTestDefaults.fresh())

        #expect(preferences.weightUnit == .kg)
        #expect(preferences.haptics)
        #expect(preferences.voiceLog)
        #expect(preferences.lastSavedAt == nil)
        #expect(preferences.distanceUnit == DistanceUnit.matching(.kg))
    }

    @Test("every row survives a relaunch through the same suite")
    func roundTrip() {
        let suite = WatchTestDefaults.fresh()
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        let first = WatchPreferences(defaults: suite)
        first.weightUnit = .lb
        first.haptics = false
        first.voiceLog = false
        first.lastSavedAt = saved

        let second = WatchPreferences(defaults: suite)

        #expect(second.weightUnit == .lb)
        #expect(!second.haptics)
        #expect(!second.voiceLog)
        #expect(second.lastSavedAt == saved)
        #expect(second.distanceUnit == DistanceUnit.matching(.lb))
    }

    @Test("the unit is written under the phone's key, which the shared store reads")
    func unitKeyMatchesStore() {
        let suite = WatchTestDefaults.fresh()
        let preferences = WatchPreferences(defaults: suite)
        preferences.weightUnit = .lb

        #expect(suite.string(forKey: Preferences.Key.weightUnit) == WeightUnit.lb.rawValue)
        #expect(Preferences.Key.weightUnit == "weightUnit")
    }
}
