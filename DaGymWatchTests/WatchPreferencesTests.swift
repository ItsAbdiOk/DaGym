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
        #expect(preferences.weekStartsMonday)
    }

    /// The phone's `Preferences.weekStartsMonday` defaults to Monday and does not sync; a watch
    /// on `Calendar.current` (Sunday-first in the US) put a Sunday session in a different week
    /// and quoted a different streak. Same default, same key, same calendar shape.
    @Test("weeks start on Monday like the phone, whatever the locale says")
    func weekStartMatchesPhone() {
        let suite = WatchTestDefaults.fresh()
        let preferences = WatchPreferences(defaults: suite)
        #expect(preferences.trainingCalendar.firstWeekday == 2)
        #expect(Preferences.Key.weekStartsMonday == "weekStartsMonday")

        preferences.weekStartsMonday = false
        #expect(preferences.trainingCalendar.firstWeekday == 1)
        #expect(suite.bool(forKey: Preferences.Key.weekStartsMonday) == false)
        #expect(!WatchPreferences(defaults: suite).weekStartsMonday)
    }

    @Test("the streak counts Monday-start weeks: a Sunday session belongs to the week before")
    func streakUsesMondayWeeks() throws {
        var sunday = Calendar(identifier: .gregorian)
        sunday.firstWeekday = 1
        // Saturday 2026-09-19; sessions Sun 13, Tue 15, Thu 17, Sat 19 with goal 4.
        let components = DateComponents(year: 2026, month: 9, day: 19, hour: 20)
        let saturday = try #require(sunday.date(from: components))
        let dates = [-6, -4, -2, 0].compactMap { sunday.date(byAdding: .day, value: $0, to: saturday) }
        let preferences = WatchPreferences(defaults: WatchTestDefaults.fresh())

        let sundayWeeks = Streaks.weekly(workoutDates: dates, weeklyGoal: 4, calendar: sunday, now: saturday)
        let watchWeeks = Streaks.weekly(
            workoutDates: dates, weeklyGoal: 4, calendar: preferences.trainingCalendar, now: saturday
        )

        #expect(sundayWeeks.current == 1)
        #expect(watchWeeks.current == 0)
        #expect(watchWeeks.thisWeekCount == 3)
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
