import Foundation
import GymCore
import Testing

@testable import DaGym

/// `Preferences.workoutLayout` (OpenGym parity 1): the saved three-way layout, its migration
/// from the older "Compact layout" toggle, and its trip through a backup.
@MainActor
@Suite("Workout layout preference")
struct WorkoutLayoutPreferenceTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a fresh install lays the workout out as cards")
    func defaultIsCards() {
        #expect(Preferences(suite: makeSuite(#function)).workoutLayout == .cards)
    }

    @Test("a lifter who had the old Compact toggle on lands on the compact layout, once")
    func legacyCompactMigrates() {
        let suite = makeSuite(#function)
        suite.set(true, forKey: Preferences.Key.compactWorkoutLayout)
        let first = Preferences(suite: suite)
        #expect(first.workoutLayout == .compact)

        // Choosing another layout sticks, even though the old key is still there.
        first.workoutLayout = .list
        #expect(Preferences(suite: suite).workoutLayout == .list)
    }

    @Test("the chosen layout survives a relaunch")
    func persists() {
        let suite = makeSuite(#function)
        Preferences(suite: suite).workoutLayout = .list
        #expect(Preferences(suite: suite).workoutLayout == .list)
        Preferences(suite: suite).workoutLayout = .cards
        #expect(Preferences(suite: suite).workoutLayout == .cards)
    }

    @Test("a backup carries the layout, and the legacy flag for older apps")
    func backupExportsBothKeys() {
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutLayout = .list
        let exported = BackupService.exportPreferences(preferences)
        #expect(exported.workoutLayout == "list")
        #expect(exported.compactWorkoutLayout == true)

        preferences.workoutLayout = .cards
        #expect(BackupService.exportPreferences(preferences).compactWorkoutLayout == false)
    }

    @Test("restoring a backup prefers the layout, falls back to the legacy flag, leaves nil alone")
    func backupImportResolves() {
        let preferences = Preferences(suite: makeSuite(#function))
        var backup = BackupPreferences()

        backup.workoutLayout = "list"
        backup.compactWorkoutLayout = true
        BackupService.applyPreferences(backup, to: preferences)
        #expect(preferences.workoutLayout == .list)

        backup.workoutLayout = nil
        backup.compactWorkoutLayout = true
        BackupService.applyPreferences(backup, to: preferences)
        #expect(preferences.workoutLayout == .compact)

        backup.compactWorkoutLayout = nil
        BackupService.applyPreferences(backup, to: preferences)
        #expect(preferences.workoutLayout == .compact, "a backup with neither key changes nothing")
    }

    @Test("reset returns the layout to cards")
    func resetClears() throws {
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.workoutLayout = .compact
        let store = try makeStore(seed: .firstLaunch)
        store.wipeAllData(preferences: preferences, effects: .inert)
        #expect(preferences.workoutLayout == .cards)
    }
}
