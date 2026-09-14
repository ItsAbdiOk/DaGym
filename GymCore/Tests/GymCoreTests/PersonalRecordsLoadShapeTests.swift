import Foundation
import Testing
@testable import GymCore

/// The load-shape half of the PR suite: bodyweight-only, assisted and weighted-bodyweight sets.
/// Expected e1RMs are hand-derived — see the note on `PersonalRecordsTests`. Split from that
/// suite only to keep either type under the 250-line body limit.
@Suite("Personal records — load shapes")
struct PersonalRecordsLoadShapeTests {
    private static let day1 = PersonalRecordsTests.day1
    private static let day2 = PersonalRecordsTests.day2
    private static let e1rm100x5 = PersonalRecordsTests.e1rm100x5
    private static let e1rm60x5 = PersonalRecordsTests.e1rm60x5
    private static let e1rm80x12 = PersonalRecordsTests.e1rm80x12

    private func set(
        kind: SetKind = .working, weight: Double, reps: Int, duration: Int? = nil,
        assistance: Double? = nil, bodyweight: Double? = nil
    ) -> PerformedSet {
        PerformedSet(
            kind: kind, weightKg: weight, reps: reps, durationSeconds: duration,
            assistanceKg: assistance, bodyweightKg: bodyweight, date: Self.day1
        )
    }

    private func isClose(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.001
    }

    // MARK: - Bodyweight-only lifts (F3)

    @Test("a bodyweight-only set earns no e1RM PR, whatever the lifter weighs")
    func bodyweightOnlySetEarnsNoE1RM() {
        // The store no longer supplies a bodyweight for `.bodyweightReps`, so this is the shape
        // air squats arrive in — and 0 kg of external load has no one-rep max.
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 12)], existing: [], workoutDate: Self.day1
        )
        #expect(!prs.contains { $0.kind == .e1rm })
    }

    @Test("bodyweight is not folded into a plain loaded set's e1RM")
    func loadedSetIgnoresBodyweightWhenAbsent() {
        // 12 air squats at 80 kg bodyweight used to estimate 113.4656 kg — a Bronze "Bodyweight
        // Squat" earned by standing up twelve times. Nothing may produce that number now.
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 12)], existing: [], workoutDate: Self.day1
        )
        #expect(!prs.contains { isClose($0.value, Self.e1rm80x12) })
    }

    @Test("a 0 kg first set earns no maxWeight/volume PR but does earn a bodyweight rep PR")
    func zeroWeightFirstSetSkipsMaxWeightAndVolume() throws {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 10)], existing: [], workoutDate: Self.day1
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
            newSets: [set(weight: 20, reps: 5)], existing: existing, workoutDate: Self.day2
        )
        #expect(prs.first { $0.kind == .maxWeight }?.value == 20)
    }

    // MARK: - Assisted lifts (F2)

    @Test("assisted e1RM is bodyweight minus assistance, and the line quotes that load")
    func assistedEffectiveWeight() throws {
        // 80 kg lifter, 20 kg of help, 5 reps → 60 kg lifted → 69.1498.
        let sets = [set(weight: 0, reps: 5, assistance: 20, bodyweight: 80)]
        let prs = PersonalRecords.evaluate(newSets: sets, existing: [], workoutDate: Self.day1)
        let e1rm = try #require(prs.first { $0.kind == .e1rm })
        #expect(isClose(e1rm.value, Self.e1rm60x5))
        #expect(e1rm.weightKg == 60)
    }

    @Test("assistance is never counted as weight lifted")
    func assistanceIsNotLoad() {
        // The store hands assistance over in `assistanceKg` with `weightKg` zeroed, so 30 kg of
        // help at 8 reps can no longer bank "Heaviest 30 kg" or "Best set 30 × 8 (240 kg)".
        let sets = [set(weight: 0, reps: 8, assistance: 30, bodyweight: 80)]
        let prs = PersonalRecords.evaluate(newSets: sets, existing: [], workoutDate: Self.day1)
        #expect(!prs.contains { $0.kind == .maxWeight })
        #expect(!prs.contains { $0.kind == .volume })
        #expect(prs.contains { $0.kind == .leastAssistance && $0.value == 30 })
    }

    @Test("less assistance raises the e1RM, so dialling help down earns the PR")
    func lessAssistanceEarnsE1RM() {
        let existing = [
            PersonalRecord(kind: .e1rm, value: Self.e1rm60x5, weightKg: 60, reps: 5, date: Self.day1)
        ]
        // Same lifter, help down from 20 to 10: 70 kg × 5, which is above 69.1498.
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 5, assistance: 10, bodyweight: 80)], existing: existing,
            workoutDate: Self.day2
        )
        let e1rm = prs.first { $0.kind == .e1rm }
        #expect(e1rm != nil)
        #expect((e1rm?.value ?? 0) > Self.e1rm60x5)
    }

    @Test("an assisted set with no bodyweight on file earns no e1RM rather than guessing")
    func assistedWithoutBodyweightEarnsNoE1RM() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 8, assistance: 20)], existing: [], workoutDate: Self.day1
        )
        #expect(!prs.contains { $0.kind == .e1rm })
        #expect(prs.contains { $0.kind == .leastAssistance })
    }

    @Test("assistance at or above bodyweight means nothing was lifted, so no e1RM")
    func assistanceAtBodyweightEarnsNoE1RM() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 8, assistance: 80, bodyweight: 80)], existing: [],
            workoutDate: Self.day1
        )
        #expect(!prs.contains { $0.kind == .e1rm })
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
        let prs = PersonalRecords.evaluate(newSets: sets, existing: existing, workoutDate: Self.day2)
        #expect(prs.first { $0.kind == .longestHold }?.value == 65)
        #expect(prs.first { $0.kind == .leastAssistance }?.value == 15)
    }

    @Test("more assistance is worse, not a record")
    func moreAssistanceIsNotBetter() {
        let existing = [
            PersonalRecord(kind: .leastAssistance, value: 10, weightKg: 0, reps: 0, date: Self.day1)
        ]
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 8, assistance: 15)], existing: existing, workoutDate: Self.day2
        )
        #expect(!prs.contains { $0.kind == .leastAssistance })
    }

    @Test("a 0-second hold earns no 'Hold 0:00' record")
    func zeroSecondHoldEarnsNothing() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 0, reps: 1, duration: 0)], existing: [], workoutDate: Self.day1
        )
        #expect(!prs.contains { $0.kind == .longestHold })
    }

    // MARK: - Weighted bodyweight (F6)

    @Test("weighted bodyweight e1RM is bodyweight plus added load, quoted as that load")
    func weightedBodyweightEffectiveWeight() throws {
        // +20 kg pull-up at 80 kg bodyweight, 5 reps → 100 kg × 5 → 115.2497.
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 20, reps: 5, bodyweight: 80)], existing: [], workoutDate: Self.day1
        )
        let e1rm = try #require(prs.first { $0.kind == .e1rm })
        #expect(isClose(e1rm.value, Self.e1rm100x5))
        #expect(e1rm.weightKg == 100)
        // The belt weight is still the load "on the bar" for max weight and volume.
        #expect(prs.first { $0.kind == .maxWeight }?.value == 20)
        #expect(prs.first { $0.kind == .volume }?.value == 100)
    }

    @Test("effectiveWeightKg is the one definition the card and the chart share")
    func effectiveWeightIsShared() {
        let assisted = set(weight: 0, reps: 5, assistance: 20, bodyweight: 80)
        let weighted = set(weight: 20, reps: 5, bodyweight: 80)
        let plain = set(weight: 100, reps: 5)
        let air = set(weight: 0, reps: 12)
        #expect(assisted.effectiveWeightKg == 60)
        #expect(weighted.effectiveWeightKg == 100)
        #expect(plain.effectiveWeightKg == 100)
        #expect(air.effectiveWeightKg == 0)
        #expect(set(weight: 0, reps: 5, assistance: 20).effectiveWeightKg == nil)
        #expect(set(weight: 0, reps: 5, assistance: 90, bodyweight: 80).effectiveWeightKg == nil)
    }
}
