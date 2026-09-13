import Foundation
import Testing
@testable import GymCore

@Suite("Personal records")
struct PersonalRecordsTests {
    static let day1 = Date(timeIntervalSince1970: 1_000_000)
    static let day2 = Date(timeIntervalSince1970: 1_100_000)
    static let day0 = Date(timeIntervalSince1970: 900_000)

    private func set(
        kind: SetKind = .working,
        weight: Double,
        reps: Int,
        duration: Int? = nil,
        assistance: Double? = nil,
        bodyweight: Double? = nil,
        date: Date = day1
    ) -> PerformedSet {
        PerformedSet(
            kind: kind, weightKg: weight, reps: reps, durationSeconds: duration,
            assistanceKg: assistance, bodyweightKg: bodyweight, date: date
        )
    }

    @Test("first ever set earns e1RM, max weight and volume PRs")
    func firstSetEarnsRecords() {
        let sets = [set(weight: 100, reps: 5)]
        let prs = PersonalRecords.evaluate(
            newSets: sets, existing: [], workoutDate: Self.day1, isBackfilled: false, latestWorkoutDate: nil
        )
        #expect(prs.contains { $0.kind == .e1rm })
        #expect(prs.contains { $0.kind == .maxWeight && $0.value == 100 })
        #expect(prs.contains { $0.kind == .volume && $0.value == 500 })
    }

    @Test("warm-ups never count toward any record")
    func warmupsExcluded() {
        let sets = [set(kind: .warmup, weight: 200, reps: 20)]
        let prs = PersonalRecords.evaluate(
            newSets: sets, existing: [], workoutDate: Self.day1, isBackfilled: false, latestWorkoutDate: nil
        )
        #expect(prs.isEmpty)
    }

    @Test("heavier weight beats the existing max weight record")
    func heavierWeightWins() {
        let existing = [PersonalRecord(kind: .maxWeight, value: 100, weightKg: 100, reps: 3, date: Self.day1)]
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 105, reps: 1)], existing: existing,
            workoutDate: Self.day2, isBackfilled: false, latestWorkoutDate: Self.day1
        )
        let maxWeight = prs.first { $0.kind == .maxWeight }
        #expect(maxWeight?.value == 105)
    }

    @Test("equal weight does not earn a new max weight record")
    func tieDoesNotCount() {
        let existing = [PersonalRecord(kind: .maxWeight, value: 100, weightKg: 100, reps: 3, date: Self.day1)]
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 100, reps: 1)], existing: existing,
            workoutDate: Self.day2, isBackfilled: false, latestWorkoutDate: Self.day1
        )
        #expect(!prs.contains { $0.kind == .maxWeight })
    }

    @Test("maxRepsAtWeight only beats the record at the same weight")
    func maxRepsAtWeightIsPerWeight() {
        let existing = [
            PersonalRecord(kind: .maxRepsAtWeight, value: 8, weightKg: 60, reps: 8, date: Self.day1),
            PersonalRecord(kind: .maxRepsAtWeight, value: 5, weightKg: 80, reps: 5, date: Self.day1)
        ]
        // More reps at a weight (100) that has no existing record still earns a PR.
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 60, reps: 6), set(weight: 100, reps: 3)], existing: existing,
            workoutDate: Self.day2, isBackfilled: false, latestWorkoutDate: Self.day1
        )
        let atWeights = prs.filter { $0.kind == .maxRepsAtWeight }.map(\.weightKg).sorted()
        #expect(atWeights == [100])
    }

    @Test("maxRepsAtWeight can return more than one weight in the same evaluation")
    func maxRepsAtWeightMultiplePerCall() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 60, reps: 8), set(weight: 80, reps: 5)], existing: [],
            workoutDate: Self.day1, isBackfilled: false, latestWorkoutDate: nil
        )
        let atWeights = prs.filter { $0.kind == .maxRepsAtWeight }.map(\.weightKg).sorted()
        #expect(atWeights == [60, 80])
    }

    @Test("longest hold and least assistance rules")
    func holdAndAssistance() {
        let existing = [
            PersonalRecord(kind: .longestHold, value: 30, weightKg: 0, reps: 0, date: Self.day1),
            PersonalRecord(kind: .leastAssistance, value: 20, weightKg: 0, reps: 0, date: Self.day1)
        ]
        let sets = [
            set(kind: .working, weight: 0, reps: 1, duration: 65),
            set(kind: .working, weight: 0, reps: 8, assistance: 15)
        ]
        let prs = PersonalRecords.evaluate(
            newSets: sets, existing: existing, workoutDate: Self.day2,
            isBackfilled: false, latestWorkoutDate: Self.day1
        )
        #expect(prs.first { $0.kind == .longestHold }?.value == 65)
        #expect(prs.first { $0.kind == .leastAssistance }?.value == 15)
    }

    @Test("more assistance is worse, not a record")
    func moreAssistanceIsNotBetter() {
        let existing = [
            PersonalRecord(kind: .leastAssistance, value: 10, weightKg: 0, reps: 0, date: Self.day1)
        ]
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 8, assistance: 15)], existing: existing,
            workoutDate: Self.day2, isBackfilled: false, latestWorkoutDate: Self.day1
        )
        #expect(!prs.contains { $0.kind == .leastAssistance })
    }

    @Test("assisted effective weight is bodyweight minus assistance for e1RM")
    func assistedEffectiveWeight() {
        let sets = [set(weight: 0, reps: 5, assistance: 20, bodyweight: 80)]
        let prs = PersonalRecords.evaluate(
            newSets: sets, existing: [], workoutDate: Self.day1, isBackfilled: false, latestWorkoutDate: nil
        )
        let e1rm = prs.first { $0.kind == .e1rm }
        let expected = try? #require(OneRepMax.estimate(weight: 60, reps: 5))
        #expect(e1rm?.value == expected)
    }

    @Test("weighted bodyweight effective weight is bodyweight plus added weight")
    func weightedBodyweightEffectiveWeight() {
        let sets = [set(weight: 20, reps: 5, bodyweight: 80)]
        let prs = PersonalRecords.evaluate(
            newSets: sets, existing: [], workoutDate: Self.day1, isBackfilled: false, latestWorkoutDate: nil
        )
        let e1rm = prs.first { $0.kind == .e1rm }
        #expect(e1rm?.value == OneRepMax.estimate(weight: 100, reps: 5))
    }

    @Test("a backfilled workout dated before the latest session earns nothing")
    func backfillBeforeLatestEarnsNothing() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 999, reps: 1, date: Self.day0)], existing: [],
            workoutDate: Self.day0, isBackfilled: true, latestWorkoutDate: Self.day2
        )
        #expect(prs.isEmpty)
    }

    @Test("a backfilled workout later than the latest session can still earn a PR")
    func backfillAfterLatestCanEarn() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 999, reps: 1, date: Self.day2)], existing: [],
            workoutDate: Self.day2, isBackfilled: true, latestWorkoutDate: Self.day1
        )
        #expect(prs.contains { $0.kind == .maxWeight })
    }

    @Test("only the best set of a kind is returned, not every improving set")
    func onlyBestReturned() {
        let sets = [set(weight: 100, reps: 1), set(weight: 110, reps: 1), set(weight: 105, reps: 1)]
        let prs = PersonalRecords.evaluate(
            newSets: sets, existing: [], workoutDate: Self.day1, isBackfilled: false, latestWorkoutDate: nil
        )
        let maxWeights = prs.filter { $0.kind == .maxWeight }
        #expect(maxWeights.count == 1)
        #expect(maxWeights.first?.value == 110)
    }

    @Test("a 0 kg first set earns no maxWeight/volume PR but does earn a bodyweight rep PR")
    func zeroWeightFirstSetSkipsMaxWeightAndVolume() throws {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 10)], existing: [],
            workoutDate: Self.day1, isBackfilled: false, latestWorkoutDate: nil
        )
        #expect(!prs.contains { $0.kind == .maxWeight })
        #expect(!prs.contains { $0.kind == .volume })
        let repsPR = try #require(prs.first { $0.kind == .maxRepsAtWeight })
        #expect(repsPR.reps == 10)
        #expect(PersonalRecords.formatLine(repsPR) == "10 reps bodyweight")
    }

    @Test("a heavier real weight still beats a stale 0 kg maxWeight record")
    func realWeightBeatsZeroBaseline() {
        let existing = [PersonalRecord(kind: .maxWeight, value: 0, weightKg: 0, reps: 0, date: Self.day1)]
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 20, reps: 5)], existing: existing,
            workoutDate: Self.day2, isBackfilled: false, latestWorkoutDate: Self.day1
        )
        #expect(prs.first { $0.kind == .maxWeight }?.value == 20)
    }

    @Test("duplicate cache rows in the same 0.25 kg bucket: reps beat the best of them, not the first")
    func maxRepsAtWeightBeatsTheBestDuplicateRow() {
        // Pre-F17 row at 60.0004 kg with 9 reps sits beside a post-fix row at 60.0 kg with 7 reps —
        // both key to the same 0.25 kg bucket. An 8-rep set should not "beat" the 7-rep row while
        // the 9-rep row still stands.
        let existing = [
            PersonalRecord(kind: .maxRepsAtWeight, value: 7, weightKg: 60.0, reps: 7, date: Self.day1),
            PersonalRecord(kind: .maxRepsAtWeight, value: 9, weightKg: 60.0004, reps: 9, date: Self.day1)
        ]
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 60.0, reps: 8)], existing: existing,
            workoutDate: Self.day2, isBackfilled: false, latestWorkoutDate: Self.day1
        )
        #expect(!prs.contains { $0.kind == .maxRepsAtWeight })
    }

    @Test("format line for each PR kind")
    func formatLines() {
        let e1rm = PersonalRecord(kind: .e1rm, value: 102.5, weightKg: 82.5, reps: 8, date: Self.day1)
        #expect(PersonalRecords.formatLine(e1rm) == "82.5 × 8 (e1RM 102.5)")

        let maxWeight = PersonalRecord(
            kind: .maxWeight, value: 100, weightKg: 100, reps: 1, date: Self.day1
        )
        #expect(PersonalRecords.formatLine(maxWeight) == "Heaviest 100 kg")

        let maxReps = PersonalRecord(
            kind: .maxRepsAtWeight, value: 12, weightKg: 60, reps: 12, date: Self.day1
        )
        #expect(PersonalRecords.formatLine(maxReps) == "12 reps at 60 kg")

        let hold = PersonalRecord(kind: .longestHold, value: 65, weightKg: 0, reps: 0, date: Self.day1)
        #expect(PersonalRecords.formatLine(hold) == "Hold 1:05")

        let assistance = PersonalRecord(
            kind: .leastAssistance, value: 15, weightKg: 0, reps: 0, date: Self.day1
        )
        #expect(PersonalRecords.formatLine(assistance) == "Assistance down to 15 kg")
    }

    @Test("format line renders in the caller's unit")
    func formatLineUnitAware() {
        // 61.235 kg -> 135.006 lb, rounds to the nearest half pound and drops the trailing .0.
        let maxWeight = PersonalRecord(
            kind: .maxWeight, value: 61.235, weightKg: 61.235, reps: 1, date: Self.day1
        )
        #expect(PersonalRecords.formatLine(maxWeight, unit: .lb) == "Heaviest 135 lb")
        #expect(PersonalRecords.formatLine(maxWeight, unit: .kg) == "Heaviest 61.25 kg")
    }
}
