// Scenario / regression pins from the engine review (docs/engine-review.md),
// continued from ProgressionScenarioTests.swift: training max, timed, assisted,
// recovery and deload-detector findings.
import Foundation
import Testing
@testable import GymCore

@Suite("Engine — review scenarios (TM, timed, assisted, recovery, deload)")
struct EngineScenarioTests {
    private func entry(_ reps: [Int], at weight: Double, rpe: [Double?]? = nil, kinds: [SetKind]? = nil,
                       daysAgo: Int = 0) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            date: Date.now.addingTimeInterval(Double(-daysAgo) * 86_400),
            sets: reps.indices.map { index in
                HistorySet(kind: kinds?[index] ?? .working, weightKg: weight, reps: reps[index],
                           effort: rpe?[index].map { Effort(rpe: $0) })
            }
        )
    }

    // MARK: F6 — training max

    @Test("F6: prescribing twice in week 1 without a cycle index never bumps the TM")
    func trainingMaxNoDoubleBump() {
        let rule = ProgressionRule.percentOfTrainingMax(scheme: .classic)
        let first = ProgressionEngine.prescribe(
            rule: rule, planned: [], history: [], stall: StallState(), trainingMaxKg: 100, weekInCycle: 1
        )
        let second = ProgressionEngine.prescribe(
            rule: rule, planned: [], history: [], stall: first.stall,
            trainingMaxKg: first.trainingMaxKg, weekInCycle: 1
        )
        #expect(first.trainingMaxKg == 100)
        #expect(second.trainingMaxKg == 100)
    }

    @Test("F6: the TM bumps once per cycle by the lift's increment, however often week 1 is prescribed")
    func trainingMaxBumpsOncePerCycle() {
        let rule = ProgressionRule.percentOfTrainingMax(scheme: .classic)
        var stall = StallState()
        var tm: Double? = 100
        var seen: [Double] = []
        // Cycle 1 (init), then 3 calls in cycle 2 week 1, then cycle 3.
        for cycle in [1, 2, 2, 2, 3] {
            let r = ProgressionEngine.prescribe(
                rule: rule, planned: [], history: [], stall: stall, trainingMaxKg: tm, weekInCycle: 1,
                cycleIndex: cycle, trainingMaxIncrementKg: 5
            )
            stall = r.stall
            tm = r.trainingMaxKg
            seen.append(tm ?? 0)
        }
        #expect(seen == [100, 105, 105, 105, 110])
    }

    @Test("F6: an AMRAP set that doesn't support the bump caps the TM")
    func trainingMaxCappedByAMRAP() {
        let rule = ProgressionRule.percentOfTrainingMax(scheme: .classic)
        // Best AMRAP: 85 × 5 → e1RM ≈ 98 → 90 % ≈ 88 — below the current 100 TM, so hold, don't bump.
        let history = [entry([5, 5, 5], at: 85, kinds: [.working, .working, .amrap])]
        let r = ProgressionEngine.prescribe(
            rule: rule, planned: [], history: history, stall: StallState(trainingMaxCycle: 1),
            trainingMaxKg: 100, weekInCycle: 1, cycleIndex: 2
        )
        #expect(r.trainingMaxKg == 100)
    }

    @Test("F15: TM initialisation uses the best recent session, not just the last (high-rep) one")
    func tmInitFromBestRecent() {
        let history = [
            entry([15, 15, 15], at: 60),
            entry([5, 5, 5], at: 100, daysAgo: 7)
        ]
        let result = ProgressionEngine.prescribe(
            rule: .percentOfTrainingMax(scheme: .classic), planned: [], history: history,
            stall: StallState(), trainingMaxKg: nil, weekInCycle: 2
        )
        #expect((result.trainingMaxKg ?? 0) > 90)
        #expect(result.reason.kind == .plan)
    }

    // MARK: F7 — timed

    @Test("F7: holding 45 s when 60 s was prescribed is a miss, and repeats 60 s")
    func timedJudgesAgainstWhatWasAsked() {
        let planned = [PlannedSetSpec(kind: .working, targetSeconds: 30)]
        let history = [ExerciseHistoryEntry(date: .now, sets: [
            HistorySet(kind: .working, weightKg: 0, reps: 1, durationSeconds: 45)
        ])]
        let result = ProgressionEngine.prescribe(
            rule: .timed(stepSeconds: 5), planned: planned, history: history,
            stall: StallState(lastTargetSeconds: 60)
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.sets[0].durationSeconds == 60)
        #expect(result.stall.lastTargetSeconds == 60)
    }

    @Test("F7: a hold stops creeping at the ceiling and hands off to load / a harder variation")
    func timedCeiling() {
        let planned = [PlannedSetSpec(kind: .working, targetSeconds: 30)]
        var stall = StallState()
        var held = 30
        var last: Prescribed?
        for _ in 0..<30 {
            let history = [ExerciseHistoryEntry(date: .now, sets: [
                HistorySet(kind: .working, weightKg: 0, reps: 1, durationSeconds: held)
            ])]
            let r = ProgressionEngine.prescribe(
                rule: .timed(stepSeconds: 5), planned: planned, history: history, stall: stall
            )
            stall = r.stall
            held = r.sets[0].durationSeconds ?? held
            last = r
        }
        #expect(held == TrainingConstants.timedCeilingSeconds)
        #expect(last?.reason.kind == .plan)
    }

    // MARK: F9 — linear + AMRAP

    @Test("F9: a missing AMRAP set holds the weight")
    func amrapMissingSet() {
        let planned = [PlannedSetSpec(kind: .working, targetReps: 8),
                       PlannedSetSpec(kind: .working, targetReps: 8),
                       PlannedSetSpec(kind: .amrap, targetReps: 8)]
        let result = ProgressionEngine.prescribe(
            rule: .linearAMRAP(incrementKg: 2.5), planned: planned,
            history: [entry([8, 8], at: 100)], stall: StallState()
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 0)
    }

    @Test("F9: 3,3,8+ at 100 is a miss on the straight sets, not an increase")
    func amrapStraightSetsMustHit() {
        let planned = [PlannedSetSpec(kind: .working, targetReps: 8),
                       PlannedSetSpec(kind: .working, targetReps: 8),
                       PlannedSetSpec(kind: .amrap, targetReps: 8)]
        let result = ProgressionEngine.prescribe(
            rule: .linearAMRAP(incrementKg: 2.5), planned: planned,
            history: [entry([3, 3, 8], at: 100, kinds: [.working, .working, .amrap])], stall: StallState()
        )
        #expect(result.reason.kind == .repeat)
        #expect(result.stall.consecutiveMisses == 1)
    }

    @Test("F9: AMRAP misses repeat first and back off 10 % on the second, feeding the stall counter")
    func amrapMissesRepeatThenBackOff() {
        let planned = [PlannedSetSpec(kind: .working, targetReps: 8),
                       PlannedSetSpec(kind: .working, targetReps: 8),
                       PlannedSetSpec(kind: .amrap, targetReps: 8)]
        let first = ProgressionEngine.prescribe(
            rule: .linearAMRAP(incrementKg: 2.5), planned: planned,
            history: [entry([8, 8, 5], at: 100, kinds: [.working, .working, .amrap])], stall: StallState()
        )
        #expect(first.reason.kind == .repeat)
        #expect(first.sets[0].weightKg == 100)
        let second = ProgressionEngine.prescribe(
            rule: .linearAMRAP(incrementKg: 2.5), planned: planned,
            history: [entry([8, 8, 6], at: 100, kinds: [.working, .working, .amrap])], stall: first.stall
        )
        #expect(second.reason.kind == .deload)
        #expect(second.sets[0].weightKg == 90)
    }

    // MARK: F10 — increment below the grid

    @Test("F10: an increase always lands above the current weight, even with a 1 kg increment")
    func incrementBelowGridStillIncreases() {
        let result = ProgressionEngine.prescribe(
            rule: .doubleProgression(low: 8, high: 12, incrementKg: 1),
            planned: [PlannedSetSpec(kind: .working, targetReps: 12)],
            history: [entry([12, 12, 12], at: 50)], stall: StallState()
        )
        #expect(result.sets[0].weightKg == 52.5)
        #expect(result.sets[0].reps == 8)
        #expect(result.reason.title == "+2.5 kg")
    }

    // MARK: F11 — recovery

    @Test("F11: chest recovers below the headline threshold within 72 h of a 10-set session")
    func recoveryClearsIn72Hours() {
        let start = Date()
        let events = (0..<10).map { _ in StimulusEvent(muscle: .chest, share: 1, effort: 0.75, date: start) }
        let now = Recovery.map(events: events, now: start)[.chest] ?? 0
        let spent72 = Recovery.map(events: events, now: start.addingTimeInterval(72 * 3600))[.chest] ?? 0
        #expect(now > TrainingConstants.recoveryHeadlineThreshold)
        #expect(spent72 < 0.3)
    }

    @Test("F11: one easy set never reads as 'still spent'")
    func singleEasySetIsFresh() {
        let now = Date()
        let spent = Recovery.map(events: [StimulusEvent(muscle: .biceps, share: 1, effort: 0.5, date: now)],
                                 now: now)[.biceps] ?? 0
        #expect(spent <= 0.3)
    }

    @Test("F11: chest trained Monday and Thursday at 10 sets reads ≤ 0.35 on Thursday morning")
    func twiceWeeklyChestIsReadyByThursday() {
        let monday = Date()
        let thursdayMorning = monday.addingTimeInterval(3 * 86_400 - 6 * 3600)
        let events = (0..<10).map { _ in StimulusEvent(muscle: .chest, share: 1, effort: 0.75, date: monday) }
        let spent = Recovery.map(events: events, now: thursdayMorning)[.chest] ?? 0
        #expect(spent <= 0.35)
    }

    @Test("F11: fatigueThreshold inverts map for recoveredBy")
    func fatigueThresholdInvertsMap() {
        let threshold = Recovery.fatigueThreshold(spent: 0.3)
        let spent = 1 - Recovery.recoveredScore(fatigue: threshold)
        #expect(abs(spent - 0.3) < 0.0001)
    }

    // MARK: F13 — deload detector

    @Test("F13: one off day is not a 3-session e1RM decline")
    func e1rmTrendOneBadDay() {
        let lift = LiftSnapshot(name: "Bench", stalls: 0, e1rmTrend: [100, 101, 94])
        #expect(DeloadDetector.evaluate(lifts: [lift], hardWeeks: 0) == nil)
    }

    @Test("F13: hard weeks alone don't trigger while every lift is still adding weight")
    func hardWeeksNeedACoSignal() {
        let rising = [LiftSnapshot(name: "Squat", stalls: 0, e1rmTrend: [100, 102.5, 105])]
        #expect(DeloadDetector.evaluate(lifts: rising, hardWeeks: 6) == nil)
        let flat = [LiftSnapshot(name: "Squat", stalls: 1, e1rmTrend: [100, 102.5, 105])]
        #expect(DeloadDetector.evaluate(lifts: flat, hardWeeks: 6) != nil)
    }

    @Test("F13: the suggestion fingerprint is stable for the same evidence and differs for new evidence")
    func fingerprintIsStable() {
        let first = DeloadSuggestion(reason: "Bench's e1RM is down 7% over its last 3 sessions")
        let same = DeloadSuggestion(reason: "Bench's e1RM is down 7% over its last 3 sessions")
        let other = DeloadSuggestion(reason: "Bench's e1RM is down 8% over its last 3 sessions")
        #expect(first.fingerprint == same.fingerprint)
        #expect(first.fingerprint != other.fingerprint)
    }

    // MARK: F18 — assisted at the floor

    @Test("F18: at zero assistance the rule hands off instead of reporting −0")
    func assistedAtFloorHandsOff() {
        let history = [ExerciseHistoryEntry(date: .now, sets: [
            HistorySet(kind: .working, weightKg: 0, reps: 8, assistanceKg: 0)
        ])]
        let result = ProgressionEngine.prescribe(
            rule: .assisted(stepKg: 2.5), planned: [PlannedSetSpec(kind: .working, targetReps: 8)],
            history: history, stall: StallState()
        )
        #expect(result.reason.kind == .plan)
        #expect(result.sets[0].assistanceKg == 0)
    }
}
