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

    // The curve's promise, stated as numbers rather than as the curve: the scale constant is
    // "one hard session's worth of primary sets", and that must read exactly half spent. The
    // old version of this test ("0 → 1, and bigger fatigue reads lower") passed for any
    // decreasing function and so proved nothing about where the display lands.
    @Test("recoveredScore: 6 set-equivalents reads exactly half, 3 reads two thirds, 12 a third")
    func recoveredScoreLandsOnKnownPoints() {
        let session = TrainingConstants.recoveryFatigueScale // 6 primary sets to failure
        #expect(Recovery.recoveredScore(fatigue: 0) == 1)
        #expect(abs(Recovery.recoveredScore(fatigue: session) - 0.5) < 1e-12)
        #expect(abs(Recovery.recoveredScore(fatigue: session / 2) - 2.0 / 3.0) < 1e-12)
        #expect(abs(Recovery.recoveredScore(fatigue: 2 * session) - 1.0 / 3.0) < 1e-12)
        #expect(abs(Recovery.recoveredScore(fatigue: 5 * session) - 1.0 / 6.0) < 1e-12)
    }

    // Hand-computed targets, not `1 - 1/(1 + f/k)` typed out a second time: with k = 6,
    // spent == f / (6 + f), so one set is 1/7 and six sets is 6/12.
    @Test("map reads an absolute set count: one hard set is 1/7 spent, six are exactly half")
    func mapReadsAnAbsoluteSetCount() throws {
        let now = Date()
        func hardSets(_ count: Int) -> [StimulusEvent] {
            (0..<count).map { _ in StimulusEvent(muscle: .chest, share: 1.0, effort: 1.0, date: now) }
        }
        #expect(abs(try #require(Recovery.map(events: hardSets(1), now: now)[.chest]) - 1.0 / 7.0) < 1e-9)
        #expect(abs(try #require(Recovery.map(events: hardSets(6), now: now)[.chest]) - 0.5) < 1e-9)
        #expect(abs(try #require(Recovery.map(events: hardSets(18), now: now)[.chest]) - 0.75) < 1e-9)
    }

    // Two secondary sets read as one primary set; an unrated set reads as three quarters of a
    // set taken to failure. Both are the definition of the unit, and both are what makes the
    // map comparable between muscles and between lifters.
    @Test("share and effort are the set-equivalent unit: half a set, three quarters of the effort")
    func shareAndEffortScaleTheSetEquivalent() throws {
        let now = Date()
        let secondary = (0..<2).map { _ in
            StimulusEvent(muscle: .triceps, share: 0.5, effort: 1.0, date: now)
        }
        #expect(abs(try #require(Recovery.fatigue(events: secondary, now: now)[.triceps]) - 1.0) < 1e-12)
        let unrated = [StimulusEvent(muscle: .triceps, share: 1.0, effort: 0.75, date: now)]
        #expect(abs(try #require(Recovery.fatigue(events: unrated, now: now)[.triceps]) - 0.75) < 1e-12)
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

@Suite("Recovery absolute scale")
struct RecoveryScaleTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func session(
        _ muscle: Muscle, sets: Int, at date: Date, share: Double = 1.0, effort: Double = 1.0
    ) -> [StimulusEvent] {
        (0..<sets).map { index in
            StimulusEvent(
                muscle: muscle, share: share, effort: effort,
                date: date.addingTimeInterval(Double(index) * 120)
            )
        }
    }

    /// The HIGH finding, as the review framed it. Monday: 2 sets of face pulls, delts a
    /// secondary mover, unrated → 2 × 0.5 × 0.75 = 0.75 set-equivalents. Wednesday: 12 sets of
    /// overhead press at RIR 1 → 12 × 0.875 = 10.5, which on its own reads 10.5 / 16.5 = 64 %.
    /// The old downward-only reference dragged itself to 3.375 on Monday and then multiplied
    /// Wednesday by 6 / 3.375 = 1.78, so *logging extra light work* pushed Wednesday to 76 %.
    @Test("a light Monday session cannot inflate Wednesday's reading")
    func lightSessionCannotInflateALaterOne() throws {
        let wednesday = start.addingTimeInterval(2 * 86_400)
        let light = session(.delts, sets: 2, at: start, share: 0.5, effort: 0.75)
        let heavy = session(.delts, sets: 12, at: wednesday, effort: 0.875)
        let now = wednesday.addingTimeInterval(3600)

        let heavyOnly = try #require(Recovery.map(events: heavy, now: now)[.delts])
        let both = try #require(Recovery.map(events: light + heavy, now: now)[.delts])
        #expect(heavyOnly > 0.6 && heavyOnly < 0.65)

        // Monday can only ever add its own (decayed) 0.75 — it can never multiply Wednesday.
        #expect(both >= heavyOnly)
        #expect(both < 0.65)
        let fatigueBoth = try #require(Recovery.fatigue(events: light + heavy, now: now)[.delts])
        let fatigueHeavy = try #require(Recovery.fatigue(events: heavy, now: now)[.delts])
        #expect(fatigueBoth - fatigueHeavy < 0.75)
    }

    /// The second half of the HIGH finding: the old reference converged, so a lifter who always
    /// did one small thing read ~50 % — the same as a full 6-set primary day — and the map
    /// stopped carrying volume at all. Habitually small work must stay small, and must still
    /// rank in volume order against other habitually small work.
    @Test("habitually small work never converges on a full session's reading")
    func habituallySmallWorkStaysSmall() throws {
        let week: TimeInterval = 7 * 86_400
        // Twelve weeks of exactly one all-out calf set…
        let calves = (0..<12).flatMap {
            session(.calves, sets: 1, at: start.addingTimeInterval(Double($0) * week))
        }
        // …and twelve weeks of forearms as a secondary mover on 4 rows: 4 × 0.5 × 0.875 = 1.75.
        let forearms = (0..<12).flatMap {
            session(
                .forearms, sets: 4, at: start.addingTimeInterval(Double($0) * week),
                share: 0.5, effort: 0.875
            )
        }
        let now = start.addingTimeInterval(11 * week + 3600)
        let calfScore = try #require(Recovery.map(events: calves, now: now)[.calves])
        let forearmScore = try #require(Recovery.map(events: forearms, now: now)[.forearms])

        #expect(calfScore < 0.2)
        #expect(forearmScore < 0.3)
        #expect(forearmScore > calfScore)
    }

    /// The MEDIUM finding: the reference used to be rebuilt from a rolling 14-day slice, so when
    /// a light session left the window the factor jumped and every muscle's number moved — a
    /// chest reading fell from 64 % to 50 % at the 14-day mark with no training in between.
    /// A workout leaving the window may now only remove its own decayed residual.
    @Test("nothing steps when an old session ages out of the caller's window")
    func nothingStepsWhenASessionAgesOut() throws {
        let now = start.addingTimeInterval(20 * 86_400)
        let old = session(
            .chest, sets: 2, at: now.addingTimeInterval(-14 * 86_400 - 3600), effort: 0.75
        )
        let recent = session(.chest, sets: 12, at: now.addingTimeInterval(-2 * 86_400), effort: 0.875)

        let withOld = try #require(Recovery.map(events: old + recent, now: now)[.chest])
        let afterItAgesOut = try #require(Recovery.map(events: recent, now: now)[.chest])
        // Half a percentage point is finer than anything the screen draws.
        #expect(abs(withOld - afterItAgesOut) < 0.005)
    }

    @Test("three identical 12-set chest sessions a week apart score identically; only decay separates them")
    func identicalSessionsScoreIdentically() throws {
        let week: TimeInterval = 7 * 86_400
        let events = session(.chest, sets: 12, at: start)
            + session(.chest, sets: 12, at: start.addingTimeInterval(week))
            + session(.chest, sets: 12, at: start.addingTimeInterval(2 * week))
        let now = start.addingTimeInterval(3 * week)
        let stimuli = try #require(Recovery.sessionStimuli(events: events, now: now)[.chest])
        #expect(stimuli.count == 3)
        #expect(stimuli.allSatisfy { abs($0.raw - 12) < 1e-9 })
        #expect(stimuli[2].remaining > stimuli[1].remaining)
        #expect(stimuli[1].remaining > stimuli[0].remaining)
    }

    @Test("deleting the middle session removes exactly that session's remaining stimulus")
    func deletingASessionRemovesOnlyItself() throws {
        let week: TimeInterval = 7 * 86_400
        let first = session(.chest, sets: 3, at: start)
        let middle = session(.chest, sets: 3, at: start.addingTimeInterval(week))
        let last = session(.chest, sets: 12, at: start.addingTimeInterval(2 * week))
        let now = start.addingTimeInterval(2 * week + 3600)
        let before = try #require(Recovery.fatigue(events: first + middle + last, now: now)[.chest])
        let after = try #require(Recovery.fatigue(events: first + last, now: now)[.chest])
        let middleRemaining = try #require(
            Recovery.sessionStimuli(events: first + middle + last, now: now)[.chest]
        )[1].remaining
        #expect(abs((before - after) - middleRemaining) < 1e-9)
    }

    @Test("a single 3-set biceps session is a plain decayed sum")
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
        #expect(abs(stimuli[0].raw - 3) < 1e-9)
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

@Suite("Stimulus attribution")
struct StimulusAttributionTests {
    @Test("a warm-up is worth nothing and a drop or rest-pause chunk is worth half a set")
    func continuationSetsAreHalfASet() {
        #expect(StimulusAttribution.setWeight(kind: .warmup) == 0)
        #expect(StimulusAttribution.setWeight(kind: .working) == 1)
        #expect(StimulusAttribution.setWeight(kind: .amrap) == 1)
        #expect(StimulusAttribution.setWeight(kind: .failure) == 1)
        #expect(StimulusAttribution.setWeight(kind: .drop) == 0.5)
        #expect(StimulusAttribution.setWeight(kind: .restPause) == 0.5)
        // A triple-drop is a working set plus two drops: 2 sets' worth of stimulus, not 3.
        let triple = [SetKind.working, .drop, .drop]
            .reduce(0.0) { $0 + StimulusAttribution.setWeight(kind: $1) }
        #expect(triple == 2)
    }

    @Test("a secondary mover takes the same share the volume charts give it")
    func secondaryUsesTheSharedWeight() {
        #expect(StimulusAttribution.share(kind: .working, isPrimary: true) == 1)
        #expect(StimulusAttribution.share(kind: .working, isPrimary: false) == Recovery.secondaryShare)
        #expect(StimulusAttribution.share(kind: .drop, isPrimary: false) == Recovery.secondaryShare / 2)
        #expect(StimulusAttribution.share(kind: .warmup, isPrimary: true) == 0)
    }

    @Test("effort: RIR 0 is 1.0, RIR 2 is 0.75, RIR 4 and beyond is 0.5, unrated is 0.75")
    func effortFollowsRIR() {
        #expect(StimulusAttribution.effort(kind: .working, rpe: 10) == 1.0)
        #expect(StimulusAttribution.effort(kind: .working, rpe: 9) == 0.875)
        #expect(StimulusAttribution.effort(kind: .working, rpe: 8) == 0.75)
        #expect(StimulusAttribution.effort(kind: .working, rpe: 6) == 0.5)
        #expect(StimulusAttribution.effort(kind: .working, rpe: 4) == 0.5)
        #expect(StimulusAttribution.effort(kind: .working, rpe: nil) == 0.75)
    }

    /// The MEDIUM finding: an unrated `.failure`/`.amrap` set used to get the same 0.75 as a set
    /// nobody rated, while `PerformedSet.isHard` counted it as maximal — two parts of the app
    /// disagreeing about the same set. Whatever `isHard` calls maximal without a rating has to
    /// be maximal here too, for every kind, including any kind added later.
    @Test("every kind isHard treats as maximal without a rating gets full effort here")
    func attributionAgreesWithIsHard() {
        for kind in SetKind.allCases {
            let set = PerformedSet(kind: kind, weightKg: 60, reps: 8, date: Date(), rpe: nil)
            let effort = StimulusAttribution.effort(kind: kind, rpe: nil)
            #expect(
                set.isHard == (effort == 1.0),
                "\(kind) disagreed: isHard \(set.isHard), effort \(effort)"
            )
        }
    }

    @Test("a rated hard set (RIR <= 1) is never scored below a rated easier one")
    func ratedHardSetsOutrankEasyOnes() {
        for rpe in stride(from: 5.0, through: 10.0, by: 0.5) {
            let set = PerformedSet(kind: .working, weightKg: 60, reps: 8, date: Date(), rpe: rpe)
            let effort = StimulusAttribution.effort(kind: .working, rpe: rpe)
            if set.isHard { #expect(effort >= 0.875) } else { #expect(effort < 0.875) }
        }
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
