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
        // Fresh stimulus, no elapsed time: fatigue == effort × share == 1, normalised by k = 6,
        // so spent == 1 - 1/(1 + 1/6) ≈ 0.143.
        let scale = TrainingConstants.recoveryFatigueScale
        #expect(abs(value - (1 - 1 / (1 + 1 / scale))) < 0.001)
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

@Suite("Recovery causal reference")
struct RecoveryReferenceTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(_ muscle: Muscle, sets: Int, at date: Date) -> [StimulusEvent] {
        (0..<sets).map { index in
            StimulusEvent(
                muscle: muscle, share: 1.0, effort: 1.0, date: date.addingTimeInterval(Double(index) * 120)
            )
        }
    }

    @Test("three identical 12-set chest sessions a week apart: the third scores no higher than the first")
    func habitualSessionNeverScoresHigher() throws {
        let week: TimeInterval = 7 * 86_400
        let events = session(.chest, sets: 12, at: start)
            + session(.chest, sets: 12, at: start.addingTimeInterval(week))
            + session(.chest, sets: 12, at: start.addingTimeInterval(2 * week))
        let now = start.addingTimeInterval(3 * week)
        let stimuli = try #require(Recovery.sessionStimuli(events: events, now: now)[.chest])
        #expect(stimuli.count == 3)
        #expect(stimuli[2].normalised <= stimuli[0].normalised)
    }

    @Test("deleting the middle session never raises chest fatigue")
    func deletingASessionNeverRaisesFatigue() throws {
        let week: TimeInterval = 7 * 86_400
        let first = session(.chest, sets: 3, at: start)
        let middle = session(.chest, sets: 3, at: start.addingTimeInterval(week))
        let last = session(.chest, sets: 12, at: start.addingTimeInterval(2 * week))
        let now = start.addingTimeInterval(2 * week + 3600)
        let before = try #require(Recovery.fatigue(events: first + middle + last, now: now)[.chest])
        let after = try #require(Recovery.fatigue(events: first + last, now: now)[.chest])
        #expect(after <= before)
        // A small habitual session made the 12-set day a shock; without it the shock is smaller.
        #expect(after < before)
    }

    @Test("a single 3-set biceps session is unchanged: the reference never rises")
    func singleSessionMatchesPlainSum() throws {
        let events = session(.biceps, sets: 3, at: start)
        let now = start.addingTimeInterval(600)
        let fatigue = try #require(Recovery.fatigue(events: events, now: now)[.biceps])
        let plain = events.reduce(0.0) { total, event in
            total + event.effort * event.share * exp(-now.timeIntervalSince(event.date) / 3600 / 24)
        }
        #expect(abs(fatigue - plain) < 1e-9)
        let stimuli = try #require(Recovery.sessionStimuli(events: events, now: now)[.biceps])
        #expect(stimuli.count == 1)
        #expect(stimuli[0].reference == TrainingConstants.recoveryFatigueScale)
    }

    @Test("sets more than the session gap apart form separate sessions")
    func sessionSplitByGap() throws {
        let gap = TrainingConstants.recoverySessionGapHours * 3600
        let events = session(.lats, sets: 2, at: start)
            + session(.lats, sets: 2, at: start.addingTimeInterval(gap + 3600))
        let now = start.addingTimeInterval(2 * gap)
        let stimuli = try #require(Recovery.sessionStimuli(events: events, now: now)[.lats])
        #expect(stimuli.count == 2)
    }
}

@Suite("Recovery retention")
struct RecoveryRetentionTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    @Test("last chest set 10 days ago → fully retained")
    func recentIsFull() {
        let retention = Recovery.retention(lastTrained: [.chest: daysAgo(10)], now: now)
        #expect(retention[.chest] == 1)
    }

    @Test("last chest set 42 days ago → exactly the floor (14 d full + one 28 d half-life)")
    func oneHalfLifeHitsFloor() throws {
        let value = try #require(Recovery.retention(lastTrained: [.chest: daysAgo(42)], now: now)[.chest])
        #expect(abs(value - TrainingConstants.retentionFloor) < 1e-9)
    }

    @Test("28 days ago sits between full and the floor")
    func partialDecay() throws {
        let value = try #require(Recovery.retention(lastTrained: [.chest: daysAgo(28)], now: now)[.chest])
        #expect(value < 1)
        #expect(value > TrainingConstants.retentionFloor)
        #expect(abs(value - pow(0.5, 0.5)) < 1e-9)
    }

    @Test("never-trained hamstrings sit at the floor and list after glutes in body order")
    func neverTrainedIsFloorInBodyOrder() {
        let retention = Recovery.retention(lastTrained: [.chest: daysAgo(1)], now: now)
        #expect(retention[.hams] == TrainingConstants.retentionFloor)
        let detrained = Recovery.detrainedMuscles(retention: retention)
        #expect(!detrained.contains { $0.muscle == .chest })
        let glutesIndex = detrained.firstIndex { $0.muscle == .glutes }
        let hamsIndex = detrained.firstIndex { $0.muscle == .hams }
        #expect(glutesIndex != nil && hamsIndex != nil)
        #expect(glutesIndex ?? 0 < hamsIndex ?? 0)
    }

    @Test("events with zero share (warm-ups) don't reset the retention clock")
    func warmupsDontCount() {
        let events = [
            StimulusEvent(muscle: .chest, share: 0, effort: 1, date: daysAgo(1)),
            StimulusEvent(muscle: .chest, share: 1, effort: 1, date: daysAgo(42))
        ]
        let retention = Recovery.retention(events: events, now: now)
        #expect(retention[.chest] == TrainingConstants.retentionFloor)
    }
}
