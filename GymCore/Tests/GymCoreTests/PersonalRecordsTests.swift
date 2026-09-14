import Foundation
import Testing
@testable import GymCore

/// Expected e1RM values here are **hand-derived**, not read back out of `OneRepMax`: asserting
/// that the code equals the code proves only that it is deterministic. Each constant below is
/// the mean of the three published formulas worked out independently:
///
///     Epley   = w · (1 + r/30)
///     Brzycki = w · 36 / (37 − r)
///     Wathen  = 100w / (48.8 + 53.8 · e^(−0.075r))
///
/// For 100 kg × 5: Epley 116.6667, Brzycki 112.5, Wathen 116.5825 → mean **115.2497**.
/// For 60 kg × 5 (0.6× the above, all three formulas being linear in w): **69.1498**.
/// For 80 kg × 12: Epley 112, Brzycki 115.2, Wathen 113.1968 → mean **113.4656**.
/// A 1-rep set is its own max by definition, so e1RM(w, 1) = w exactly.
@Suite("Personal records")
struct PersonalRecordsTests {
    static let day1 = Date(timeIntervalSince1970: 1_000_000)
    static let day2 = Date(timeIntervalSince1970: 1_100_000)

    /// e1RM of 100 kg × 5 reps, worked out by hand (see the suite note).
    static let e1rm100x5 = 115.2497
    /// e1RM of 60 kg × 5 reps.
    static let e1rm60x5 = 69.1498
    /// e1RM of 80 kg × 12 reps — the number an 80 kg lifter's air squats used to bank.
    static let e1rm80x12 = 113.4656

    private static let tolerance = 0.001

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

    private func isClose(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < Self.tolerance
    }

    // MARK: - The basic rules

    @Test("first ever set earns e1RM, max weight and volume PRs, with hand-derived numbers")
    func firstSetEarnsRecords() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 100, reps: 5)], existing: [], workoutDate: Self.day1
        )
        #expect(isClose(prs.first { $0.kind == .e1rm }?.value, Self.e1rm100x5))
        #expect(prs.contains { $0.kind == .maxWeight && $0.value == 100 })
        #expect(prs.contains { $0.kind == .volume && $0.value == 500 })
    }

    @Test("a single rep is its own one-rep max")
    func singleRepIsItsOwnMax() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 142.5, reps: 1)], existing: [], workoutDate: Self.day1
        )
        #expect(prs.first { $0.kind == .e1rm }?.value == 142.5)
    }

    @Test("warm-ups never count toward any record")
    func warmupsExcluded() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(kind: .warmup, weight: 200, reps: 10)], existing: [], workoutDate: Self.day1
        )
        #expect(prs.isEmpty)
    }

    @Test("heavier weight beats the existing max weight record")
    func heavierWeightWins() {
        let existing = [PersonalRecord(kind: .maxWeight, value: 100, weightKg: 100, reps: 3, date: Self.day1)]
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 105, reps: 1)], existing: existing, workoutDate: Self.day2
        )
        #expect(prs.first { $0.kind == .maxWeight }?.value == 105)
    }

    @Test("equal weight does not earn a new max weight record")
    func tieDoesNotCount() {
        let existing = [PersonalRecord(kind: .maxWeight, value: 100, weightKg: 100, reps: 3, date: Self.day1)]
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 100, reps: 1)], existing: existing, workoutDate: Self.day2
        )
        #expect(!prs.contains { $0.kind == .maxWeight })
    }

    @Test("only the best set of a kind is returned, not every improving set")
    func onlyBestReturned() {
        let sets = [set(weight: 100, reps: 1), set(weight: 110, reps: 1), set(weight: 105, reps: 1)]
        let prs = PersonalRecords.evaluate(newSets: sets, existing: [], workoutDate: Self.day1)
        let maxWeights = prs.filter { $0.kind == .maxWeight }
        #expect(maxWeights.count == 1)
        #expect(maxWeights.first?.value == 110)
    }

    // MARK: - maxRepsAtWeight

    @Test("maxRepsAtWeight only beats the record at the same weight")
    func maxRepsAtWeightIsPerWeight() {
        let existing = [
            PersonalRecord(kind: .maxRepsAtWeight, value: 8, weightKg: 60, reps: 8, date: Self.day1),
            PersonalRecord(kind: .maxRepsAtWeight, value: 5, weightKg: 80, reps: 5, date: Self.day1)
        ]
        // More reps at a weight (100) that has no existing record still earns a PR.
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 60, reps: 6), set(weight: 100, reps: 3)], existing: existing,
            workoutDate: Self.day2
        )
        #expect(prs.filter { $0.kind == .maxRepsAtWeight }.map(\.weightKg).sorted() == [100])
    }

    @Test("maxRepsAtWeight can return more than one weight in the same evaluation")
    func maxRepsAtWeightMultiplePerCall() {
        let prs = PersonalRecords.evaluate(
            newSets: [set(weight: 60, reps: 8), set(weight: 80, reps: 5)], existing: [],
            workoutDate: Self.day1
        )
        #expect(prs.filter { $0.kind == .maxRepsAtWeight }.map(\.weightKg).sorted() == [60, 80])
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
            newSets: [set(weight: 60.0, reps: 8)], existing: existing, workoutDate: Self.day2
        )
        #expect(!prs.contains { $0.kind == .maxRepsAtWeight })
    }

    // MARK: - Formatting

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
