import Foundation
import Testing

@testable import GymCore

@Suite("CoachEvalScoring")
struct CoachEvalScoringTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func set(
        _ exercise: String, _ kg: Double, reps: Int = 5, daysAgo: Double, muscles: [Muscle] = [.chest]
    ) -> CoachEvalScoring.HistorySet {
        CoachEvalScoring.HistorySet(
            exercise: exercise, primaryMuscles: muscles, weightKg: kg, reps: reps,
            date: now.addingTimeInterval(-daysAgo * 86_400)
        )
    }

    @Test("recent bests take the heaviest set per exercise inside the window, case-insensitively")
    func recentBests() {
        let history = [
            Self.set("Barbell Squat", 100, daysAgo: 3), Self.set("barbell squat", 110, daysAgo: 10),
            Self.set("Barbell Squat", 120, daysAgo: 40), Self.set("Bench", 0, daysAgo: 1)
        ]
        let since = Self.now.addingTimeInterval(-28 * 86_400)
        let bests = CoachEvalScoring.recentBestsKg(history: history, since: since)
        #expect(bests == ["barbell squat": 110])
    }

    @Test("weight deviation is signed percent of the best and the band is −15…+5")
    func weightDeviation() throws {
        let proposed = [
            CoachEvalScoring.ProposedExercise(
                exercise: "Barbell Squat", primaryMuscles: [.quads], workingSets: 3, weightKg: 90
            ),
            CoachEvalScoring.ProposedExercise(
                exercise: "Bench", primaryMuscles: [.chest], workingSets: 3, weightKg: 120
            ),
            CoachEvalScoring.ProposedExercise(
                exercise: "Row", primaryMuscles: [.lats], workingSets: 3, weightKg: nil
            ),
            CoachEvalScoring.ProposedExercise(
                exercise: "New", primaryMuscles: [.lats], workingSets: 3, weightKg: 40
            )
        ]
        let checks = CoachEvalScoring.weightChecks(
            proposed: proposed, bestsKg: ["barbell squat": 100, "bench": 100, "row": 60]
        )
        #expect(checks.count == 2)
        let squat = try #require(checks.first { $0.exercise == "Barbell Squat" })
        #expect(squat.deviationPercent == -10)
        #expect(squat.isAcceptable())
        let bench = try #require(checks.first { $0.exercise == "Bench" })
        #expect(bench.deviationPercent == 20)
        #expect(!bench.isAcceptable())
        #expect(CoachEvalScoring.weightScore(checks) == 0.5)
        #expect(CoachEvalScoring.worstDeviationPercent(checks) == 20)
        #expect(CoachEvalScoring.weightScore([]) == nil)
        #expect(CoachEvalScoring.weightScore(checks, band: -30...25) == 1)
    }

    @Test("weekly sets split across primary muscles and scale by times per week")
    func weeklySets() {
        let proposed = [
            CoachEvalScoring.ProposedExercise(
                exercise: "Deadlift", primaryMuscles: [.hams, .glutes], workingSets: 4, weightKg: nil,
                timesPerWeek: 2
            ),
            CoachEvalScoring.ProposedExercise(
                exercise: "Curl", primaryMuscles: [.biceps], workingSets: 3, weightKg: nil, timesPerWeek: 1
            )
        ]
        let sets = CoachEvalScoring.proposedWeeklySets(proposed)
        #expect(sets[.hams] == 4)
        #expect(sets[.glutes] == 4)
        #expect(sets[.biceps] == 3)

        let history = [
            Self.set("Deadlift", 100, daysAgo: 2, muscles: [.hams, .glutes]),
            Self.set("Deadlift", 100, daysAgo: 2, muscles: [.hams, .glutes]),
            Self.set("Curl", 20, daysAgo: 9, muscles: [.biceps])
        ]
        let recent = CoachEvalScoring.recentWeeklySets(history: history, now: Self.now)
        #expect(recent == [.hams: 1, .glutes: 1])
    }

    @Test("the volume verdict compares totals with a 20% / two-set tolerance")
    func volumeVerdict() {
        let recent: [Muscle: Double] = [.chest: 10, .lats: 10]
        #expect(CoachEvalScoring.volumeVerdict(recent: recent, proposed: [.chest: 11, .lats: 11]) == .ok)
        #expect(CoachEvalScoring.volumeVerdict(recent: recent, proposed: [.chest: 14, .lats: 12]) == .high)
        #expect(CoachEvalScoring.volumeVerdict(recent: recent, proposed: [.chest: 6, .lats: 6]) == .low)
        #expect(CoachEvalScoring.volumeVerdict(recent: recent, proposed: [:]) == .none)
        // A near-empty history: two sets of slack, not 20% of nothing.
        #expect(CoachEvalScoring.volumeVerdict(recent: [:], proposed: [.chest: 2]) == .ok)
        #expect(CoachEvalScoring.volumeVerdict(recent: [:], proposed: [.chest: 3]) == .high)
    }

    @Test("the volume score follows the scenario's expectation")
    func volumeScore() {
        #expect(CoachEvalScoring.volumeScore(.high, expectation: .atMostRecent) == 0)
        #expect(CoachEvalScoring.volumeScore(.low, expectation: .atMostRecent) == 1)
        #expect(CoachEvalScoring.volumeScore(.low, expectation: .atLeastRecent) == 0)
        #expect(CoachEvalScoring.volumeScore(.high, expectation: .atLeastRecent) == 1)
        #expect(CoachEvalScoring.volumeScore(.high, expectation: .any) == 1)
        #expect(CoachEvalScoring.volumeScore(.none, expectation: .atLeastRecent) == nil)
    }

    @Test("evidence is the fraction of keyword groups mentioned")
    func evidence() {
        let reply = "Your bench has stalled at 100 kg for four weeks, and RPE has been high."
        let score = CoachEvalScoring.evidenceScore(
            reply: reply, keywordGroups: [["stall", "plateau"], ["rpe", "fatigue"], ["deload"]]
        )
        #expect(score == 2.0 / 3.0)
        #expect(CoachEvalScoring.evidenceScore(reply: reply, keywordGroups: []) == nil)
    }
}
