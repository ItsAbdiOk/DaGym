import Foundation
import GymCore
import Testing

@testable import DaGym

/// The goal line on Home's bodyweight tile (OpenGym parity 50): wording per state, and the
/// lb display rounding it inherits from `Preferences.formatWeight`.
@MainActor
@Suite("Home bodyweight tile goal line")
struct BodyweightTileGoalTests {
    private func makePreferences(_ name: String, goalKg: Double?, unit: WeightUnit = .kg) -> Preferences {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let preferences = Preferences(suite: defaults)
        preferences.weightUnit = unit
        preferences.bodyweightGoalKg = goalKg
        return preferences
    }

    @Test("no goal: no line, the tile is unchanged")
    func noGoal() {
        let preferences = makePreferences(#function, goalKg: nil)
        #expect(BodyweightTile.goalLine(kg: 82.1, deltaKg: -1.4, preferences: preferences) == nil)
        #expect(BodyweightTile.status(kg: 82.1, deltaKg: -1.4, preferences: preferences) == nil)
    }

    @Test("no reading yet: no line either, even with a goal")
    func noReading() {
        let preferences = makePreferences(#function, goalKg: 80)
        #expect(BodyweightTile.goalLine(kg: nil, deltaKg: nil, preferences: preferences) == nil)
    }

    @Test("short of the goal, above or below it, reads \"N to go\"")
    func toGo() throws {
        let preferences = makePreferences(#function, goalKg: 80)
        // 2.1 kg on the quarter-kg display grid rounds to "2": the tile never shows a stray tenth.
        let above = try #require(BodyweightTile.goalLine(kg: 82.1, deltaKg: -1.4, preferences: preferences))
        #expect(above.text == "2 to go")
        #expect(!above.isCelebratory)
        let below = try #require(BodyweightTile.goalLine(kg: 76.5, deltaKg: 0.5, preferences: preferences))
        #expect(below.text == "3.5 to go")
    }

    @Test("reaching the goal celebrates while the month still shows movement, then goes quiet")
    func reachedThenQuiet() throws {
        let preferences = makePreferences(#function, goalKg: 80)
        let justReached = try #require(
            BodyweightTile.goalLine(kg: 80, deltaKg: -1.4, preferences: preferences)
        )
        #expect(justReached.text == "Goal reached")
        #expect(justReached.isCelebratory)

        let held = try #require(BodyweightTile.goalLine(kg: 80.1, deltaKg: 0.05, preferences: preferences))
        #expect(held.text == "At goal")
        #expect(!held.isCelebratory)
        let firstReading = try #require(
            BodyweightTile.goalLine(kg: 80, deltaKg: nil, preferences: preferences)
        )
        #expect(firstReading.text == "At goal")
    }

    @Test("lb: the remaining distance rounds to the half-pound grid, never to a stray decimal")
    func poundsRounding() throws {
        let preferences = makePreferences(#function, goalKg: 80, unit: .lb)
        // 2.1 kg is 4.63 lb → "4.5"; the goal itself shows as 176.5 lb (80 kg = 176.37).
        let line = try #require(BodyweightTile.goalLine(kg: 82.1, deltaKg: -1.4, preferences: preferences))
        #expect(line.text == "4.5 to go")
        // 0.2 kg (0.44 lb) is still half a pound off in lb…
        #expect(BodyweightTile.goalLine(kg: 80.2, deltaKg: -1, preferences: preferences)?.text == "0.5 to go")
        // …and 0.1 kg (0.22 lb) rounds to zero: reached.
        let reached = BodyweightTile.goalLine(kg: 80.1, deltaKg: -1, preferences: preferences)
        #expect(reached?.text == "Goal reached")
    }

    @Test("the delta colour follows the goal: green only when moving toward it")
    func trendFollowsGoal() {
        let preferences = makePreferences(#function, goalKg: 80)
        #expect(BodyweightTile.status(kg: 82, deltaKg: -1, preferences: preferences)?.trend == .toward)
        #expect(BodyweightTile.status(kg: 82, deltaKg: 1, preferences: preferences)?.trend == .away)
        #expect(BodyweightTile.status(kg: 82, deltaKg: nil, preferences: preferences)?.trend == .flat)
    }
}
