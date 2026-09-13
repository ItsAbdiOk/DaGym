import Foundation
import GymCore
import Testing

@testable import DaGym

@Suite("RuleState round trip")
struct RuleStateTests {
    @Test("a non-classic wave scheme survives from(_:).rule unchanged")
    func nonClassicWaveRoundTrips() {
        let wave = WaveScheme(weeks: [
            1: [WaveScheme.WeekSet(percent: 0.6, reps: 5, isAMRAP: false)],
            2: [WaveScheme.WeekSet(percent: 0.7, reps: 3, isAMRAP: true)]
        ])
        let rule = ProgressionRule.percentOfTrainingMax(scheme: wave)
        let state = RuleState.from(rule)
        #expect(state.rule == rule)
    }

    @Test("a 20-rep bodyweight ceiling survives from(_:).rule unchanged")
    func bodyweightCeilingRoundTrips() {
        let rule = ProgressionRule.bodyweight(repCeiling: 20, maxSets: 5)
        let state = RuleState.from(rule)
        #expect(state.rule == rule)
    }

    @Test("a non-default timed step survives from(_:).rule unchanged")
    func timedStepRoundTrips() {
        let rule = ProgressionRule.timed(stepSeconds: 45)
        let state = RuleState.from(rule)
        #expect(state.rule == rule)
    }

    @Test("switching kind away and back to a fresh default doesn't resurrect a stale original")
    func freshStateStillUsesDefaults() {
        let state = RuleState()
        #expect(state.rule == .doubleProgression(low: 6, high: 8, incrementKg: 2.5))
    }

    @Test("linear/double-progression/AMRAP/RPE/assisted still round trip via the exposed knobs")
    func exposedKnobsStillRoundTrip() {
        for rule: ProgressionRule in [
            .linear(incrementKg: 4), .doubleProgression(low: 4, high: 10, incrementKg: 1.25),
            .linearAMRAP(incrementKg: 2), .rpeBased(targetRPE: 7.5), .assisted(stepKg: 5)
        ] {
            #expect(RuleState.from(rule).rule == rule)
        }
    }
}
