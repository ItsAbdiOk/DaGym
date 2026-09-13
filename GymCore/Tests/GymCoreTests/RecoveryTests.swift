import Foundation
import Testing
@testable import GymCore

@Suite("Recovery")
struct RecoveryTests {
    @Test("a warm-up's zero share contributes zero fatigue")
    func zeroShareContributesNothing() {
        let event = StimulusEvent(muscle: .chest, share: 0, effort: 1.0, date: Date())
        let map = Recovery.fatigue(events: [event], now: Date())
        #expect(map[.chest] == 0)
    }

    @Test("fatigue decays to half at t = τ·ln2")
    func decayHalvesAtHalfLife() throws {
        let tau = Muscle.chest.recoveryTimeConstantHours
        let start = Date()
        let halfLife = tau * log(2)
        let now = start.addingTimeInterval(halfLife * 3600)
        let event = StimulusEvent(muscle: .chest, share: 1.0, effort: 1.0, date: start)
        let map = Recovery.fatigue(events: [event], now: now)
        let value = try #require(map[.chest])
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test("small muscles recover faster than large ones after 36 hours")
    func smallMusclesRecoverFaster() {
        let start = Date()
        let now = start.addingTimeInterval(36 * 3600)
        // biceps: τ = 24h (small). glutes: τ = 48h (large). Same stimulus, same time elapsed.
        let biceps = StimulusEvent(muscle: .biceps, share: 1.0, effort: 1.0, date: start)
        let glutes = StimulusEvent(muscle: .glutes, share: 1.0, effort: 1.0, date: start)
        let fatigueMap = Recovery.fatigue(events: [biceps, glutes], now: now)
        let bicepsScore = Recovery.recoveredScore(fatigue: fatigueMap[.biceps] ?? 0)
        let glutesScore = Recovery.recoveredScore(fatigue: fatigueMap[.glutes] ?? 0)
        #expect(bicepsScore > glutesScore)
    }

    @Test("recoveredScore saturates to 1 at zero fatigue and shrinks as fatigue grows")
    func recoveredScoreSaturates() {
        #expect(Recovery.recoveredScore(fatigue: 0) == 1)
        #expect(Recovery.recoveredScore(fatigue: 1) < Recovery.recoveredScore(fatigue: 0))
        #expect(Recovery.recoveredScore(fatigue: 10) > 0)
    }

    @Test("map inverts recoveredScore into 0 fresh...1 spent")
    func mapInvertsScore() throws {
        let event = StimulusEvent(muscle: .chest, share: 1.0, effort: 1.0, date: Date())
        let map = Recovery.map(events: [event], now: Date())
        let value = try #require(map[.chest])
        // Fresh stimulus, no elapsed time: fatigue == effort × share == 1, so spent == 1 - 1/(1+1) == 0.5.
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test("recoveredBy solves for the time fatigue drops below the threshold")
    func recoveredBySolvesForTime() {
        let tau = 24.0
        let seconds = Recovery.recoveredBy(fatigue: 1.0, tau: tau, threshold: 0.3)
        #expect(seconds > 0)
        let hours = seconds / 3600
        let decayedFatigue = 1.0 * exp(-hours / tau)
        #expect(abs(decayedFatigue - 0.3) < 0.01)
    }

    @Test("recoveredBy is zero once already below threshold")
    func recoveredByZeroWhenAlreadyRecovered() {
        #expect(Recovery.recoveredBy(fatigue: 0.1, tau: 24, threshold: 0.3) == 0)
    }

    @Test("headline reports nothing logged yet for an empty map")
    func headlineEmptyMap() {
        let headline = Recovery.headline(map: [:])
        #expect(headline.title == "Nothing logged yet")
    }

    @Test("headline reports everything's fresh when nothing is above the threshold")
    func headlineEverythingFresh() {
        let headline = Recovery.headline(map: [.chest: 0.1, .quads: 0.05])
        #expect(headline.title == "Everything's fresh")
    }

    @Test("headline names the most fatigued muscle")
    func headlinePicksMostFatigued() {
        let headline = Recovery.headline(map: [.chest: 0.9, .quads: 0.1, .biceps: 0.5])
        #expect(headline.title == "Chest still spent")
        #expect(headline.body.contains("Quads"))
    }
}
