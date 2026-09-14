import Foundation
import Testing
@testable import GymCore

/// `ExerciseSeries.e1rm` over assisted and weighted-bodyweight sets — the chart must plot the
/// same effective load the PR cache banks. Expected values are hand-derived; see the note on
/// `ExerciseSeriesTests`.
@Suite("Exercise series — load shapes")
struct ExerciseSeriesLoadShapeTests {
    private let day1 = Date(timeIntervalSince1970: 0)
    private let day2 = Date(timeIntervalSince1970: 86400)

    private func set(
        kind: SetKind = .working, weight: Double, reps: Int,
        assistance: Double? = nil, bodyweight: Double? = nil
    ) -> PerformedSet {
        PerformedSet(
            kind: kind, weightKg: weight, reps: reps, assistanceKg: assistance,
            bodyweightKg: bodyweight, date: day1
        )
    }

    private func isClose(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.001
    }

    @Test("a weighted-bodyweight session charts the same e1RM the PR cache banks")
    func weightedBodyweightE1RMMatchesThePRCache() {
        // +20 kg pull-up at 80 kg bodyweight for 5 reps is a 100 kg × 5 lift. The chart used to
        // plot 23 (the belt alone) while the exercise card quoted 117 from the PR cache.
        let sessions = [
            ExerciseSession(date: day1, sets: [set(weight: 20, reps: 5, bodyweight: 80)])
        ]
        let series = ExerciseSeries.e1rm(sessions: sessions)
        #expect(series.count == 1)
        #expect(isClose(series[0].value, ExerciseSeriesTests.e1rm100x5))
    }

    @Test("an assisted session charts bodyweight minus assistance, and rises as help comes off")
    func assistedE1RMUsesNetLoad() {
        let sessions = [
            ExerciseSession(date: day1, sets: [set(weight: 0, reps: 8, assistance: 30, bodyweight: 80)]),
            ExerciseSession(date: day2, sets: [set(weight: 0, reps: 8, assistance: 10, bodyweight: 80)])
        ]
        let series = ExerciseSeries.e1rm(sessions: sessions)
        #expect(series.count == 2)
        // 50 kg × 8 then 70 kg × 8 — the line climbs as the lifter gets stronger.
        #expect(isClose(series[0].value, ExerciseSeriesTests.e1rm50x8))
        #expect(series[1].value > series[0].value)
    }

    @Test("an assisted top set plots 0 load, never the assistance dialled in")
    func assistedTopSetIsNotTheAssistance() {
        let sessions = [
            ExerciseSession(date: day1, sets: [set(weight: 0, reps: 8, assistance: 30, bodyweight: 80)])
        ]
        #expect(ExerciseSeries.topSet(sessions: sessions).map(\.value) == [0])
        #expect(ExerciseSeries.volume(sessions: sessions).map(\.value) == [0])
    }

    @Test("a bodyweight-only session has no e1RM point at all")
    func bodyweightOnlyHasNoE1RM() {
        let sessions = [ExerciseSession(date: day1, sets: [set(weight: 0, reps: 12)])]
        #expect(ExerciseSeries.e1rm(sessions: sessions).isEmpty)
    }

    @Test("13-rep sets are excluded from e1RM but count toward volume")
    func thirteenRepsExcludedFromE1RMOnly() {
        let sessions = [ExerciseSession(date: day1, sets: [set(weight: 60, reps: 13)])]
        #expect(ExerciseSeries.e1rm(sessions: sessions).isEmpty)
        let volume = ExerciseSeries.volume(sessions: sessions)
        #expect(volume.count == 1)
        #expect(volume[0].value == 60 * 13)
    }
}
