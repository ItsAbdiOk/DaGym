// swiftlint:disable large_tuple
import Foundation
import Testing
@testable import GymCore

@Suite("Auto-fill")
struct AutoFillTests {
    @Test("weight formatting drops a trailing .0")
    func weightFormat() {
        #expect(WeightFormat.kg(82.5) == "82.5")
        #expect(WeightFormat.kg(80) == "80")
        #expect(WeightFormat.kg(0) == "0")
    }

    @Test("matches previous sets by position within the same kind")
    func matchesByPosition() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.warmup, 10, nil, nil),
            (.working, 8, nil, nil),
            (.working, 8, nil, nil)
        ]
        let previous = [
            PreviousSet(kind: .warmup, weightKg: 20, reps: 10, durationSeconds: nil),
            PreviousSet(kind: .working, weightKg: 80, reps: 8, durationSeconds: nil),
            PreviousSet(kind: .working, weightKg: 82.5, reps: 7, durationSeconds: nil)
        ]
        let result = AutoFill.prescriptions(planned: planned, previous: previous, incrementKg: 2.5)
        #expect(result.count == 3)
        #expect(result[0].weightKg == 20 && result[0].reps == 10)
        #expect(result[1].weightKg == 80 && result[1].reps == 8)
        #expect(result[2].weightKg == 82.5 && result[2].reps == 7)
        #expect(result.allSatisfy { $0.reason == "Same as last time" })
        #expect(result[1].previous == "80 × 8")
    }

    @Test("working sets only match previous working sets, not warm-ups")
    func matchesOnlyWithinSameKind() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, 8, 60, nil)
        ]
        let previous = [
            PreviousSet(kind: .warmup, weightKg: 20, reps: 10, durationSeconds: nil)
        ]
        let result = AutoFill.prescriptions(planned: planned, previous: previous, incrementKg: 2.5)
        #expect(result[0].previous == nil)
        #expect(result[0].weightKg == 60)
        #expect(result[0].reason == "From your plan")
    }

    @Test("when a previous exists, last session wins over the plan's target weight")
    func previousWinsOverPlan() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, nil, 90, nil)
        ]
        let previous = [PreviousSet(kind: .working, weightKg: 80, reps: 8, durationSeconds: nil)]
        let result = AutoFill.prescriptions(planned: planned, previous: previous, incrementKg: 2.5)
        // The plan target is a starting point; what you actually lifted last time is current.
        #expect(result[0].weightKg == 80)
        #expect(result[0].reps == 8)
        #expect(result[0].previous == "80 × 8")
    }

    @Test("no previous, no plan target: reason invites the first entry")
    func noPreviousNoTarget() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, nil, nil, nil)
        ]
        let result = AutoFill.prescriptions(planned: planned, previous: [], incrementKg: 2.5)
        #expect(result[0].weightKg == 0)
        #expect(result[0].reps == 0)
        #expect(result[0].reason == "First time — enter a weight")
    }

    @Test("timed sets format previous as m:ss")
    func timedPrevious() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, nil, nil, 60)
        ]
        let previous = [PreviousSet(kind: .working, weightKg: 0, reps: 1, durationSeconds: 45)]
        let result = AutoFill.prescriptions(planned: planned, previous: previous, incrementKg: 2.5)
        #expect(result[0].previous == "0:45")
        #expect(result[0].durationSeconds == 45)
    }

    @Test("a plan target edited after the last session overrides that session")
    func updatedPlanWinsOverOlderSession() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, 5, 100, nil)
        ]
        let previous = [PreviousSet(kind: .working, weightKg: 80, reps: 8, durationSeconds: nil)]
        let sessionDate = Date(timeIntervalSince1970: 1_000)
        let result = AutoFill.prescriptions(
            planned: planned, previous: previous,
            planUpdatedAt: sessionDate.addingTimeInterval(60), previousDate: sessionDate
        )
        #expect(result[0].weightKg == 100)
        #expect(result[0].reps == 5)
        #expect(result[0].previous == nil)
        #expect(result[0].reason == "From your updated plan")
    }

    @Test("a plan edited before the last session does not override it")
    func staleplanLosesToSession() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, 5, 100, nil)
        ]
        let previous = [PreviousSet(kind: .working, weightKg: 80, reps: 8, durationSeconds: nil)]
        let sessionDate = Date(timeIntervalSince1970: 1_000)
        let result = AutoFill.prescriptions(
            planned: planned, previous: previous,
            planUpdatedAt: sessionDate.addingTimeInterval(-60), previousDate: sessionDate
        )
        #expect(result[0].weightKg == 80)
        #expect(result[0].reason == "Same as last time")
    }

    @Test("a newer plan with only a rep target still defers to last session's load")
    func newerPlanWithoutLoadTargetKeepsPrevious() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, 5, nil, nil)
        ]
        let previous = [PreviousSet(kind: .working, weightKg: 80, reps: 8, durationSeconds: nil)]
        let sessionDate = Date(timeIntervalSince1970: 1_000)
        let result = AutoFill.prescriptions(
            planned: planned, previous: previous,
            planUpdatedAt: sessionDate.addingTimeInterval(60), previousDate: sessionDate
        )
        // A rep-only edit has no load to prescribe; the previous session still fills the weight.
        #expect(result[0].weightKg == 80)
        #expect(result[0].reason == "Same as last time")
    }

    @Test("a newer timed plan prescribes the plan's seconds")
    func newerTimedPlan() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, nil, nil, 90)
        ]
        let previous = [PreviousSet(kind: .working, weightKg: 0, reps: 1, durationSeconds: 45)]
        let sessionDate = Date(timeIntervalSince1970: 1_000)
        let result = AutoFill.prescriptions(
            planned: planned, previous: previous,
            planUpdatedAt: sessionDate.addingTimeInterval(1), previousDate: sessionDate
        )
        #expect(result[0].durationSeconds == 90)
        #expect(result[0].reason == "From your updated plan")
    }

    @Test("a planned set beyond last session's count repeats the last matched set, no ghost")
    func extraPlannedSetRepeatsLast() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.working, 8, 60, nil),
            (.working, 8, 60, nil),
            (.working, 8, 60, nil)
        ]
        let previous = [
            PreviousSet(kind: .working, weightKg: 80, reps: 8, durationSeconds: nil),
            PreviousSet(kind: .working, weightKg: 82.5, reps: 6, durationSeconds: nil)
        ]
        let result = AutoFill.prescriptions(planned: planned, previous: previous)
        #expect(result[2].weightKg == 82.5)
        #expect(result[2].reps == 6)
        #expect(result[2].previous == nil)
        #expect(result[2].reason == "Like your last set")
        #expect(result[1].reason == "Same as last time")
    }

    @Test("an extra warm-up repeats the last warm-up, not the last working set")
    func extraSetRepeatsWithinKind() {
        let planned: [(kind: SetKind, targetReps: Int?, targetWeightKg: Double?, targetSeconds: Int?)] = [
            (.warmup, 10, nil, nil),
            (.warmup, 10, nil, nil)
        ]
        let previous = [
            PreviousSet(kind: .warmup, weightKg: 20, reps: 10, durationSeconds: nil),
            PreviousSet(kind: .working, weightKg: 80, reps: 8, durationSeconds: nil)
        ]
        let result = AutoFill.prescriptions(planned: planned, previous: previous)
        #expect(result[1].weightKg == 20)
        #expect(result[1].reason == "Like your last set")
    }
}
// swiftlint:enable large_tuple
