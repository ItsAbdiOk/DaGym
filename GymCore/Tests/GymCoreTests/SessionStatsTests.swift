import Foundation
import Testing
@testable import GymCore

@Suite("Session stats")
struct SessionStatsTests {
    private func set(kind: SetKind = .working, weight: Double, reps: Int) -> PerformedSet {
        PerformedSet(kind: kind, weightKg: weight, reps: reps, date: Date())
    }

    @Test("volume sums weight times reps, excluding warm-ups")
    func volume() {
        let sets = [
            set(kind: .warmup, weight: 20, reps: 10),
            set(weight: 100, reps: 5),
            set(weight: 100, reps: 5)
        ]
        #expect(SessionStats.volumeKg(sets) == 1000)
    }

    @Test("bodyweight sets with zero weight contribute zero volume")
    func bodyweightContributesZero() {
        let sets = [set(weight: 0, reps: 12)]
        #expect(SessionStats.volumeKg(sets) == 0)
    }

    @Test("muscles hit normalises 0 to 1, with secondary movers at the shared secondary share")
    func musclesHit() {
        let sets: [(primary: [Muscle], secondary: [Muscle], completedCount: Int)] = [
            (primary: [.chest], secondary: [.triceps], completedCount: 4)
        ]
        let hit = SessionStats.musclesHit(sets: sets)
        #expect(hit[.chest] == 1.0)
        #expect(hit[.triceps] == SessionStats.secondaryMuscleShare)
    }

    @Test("multiple exercises combine, capped at 1")
    func musclesHitCaps() {
        let sets: [(primary: [Muscle], secondary: [Muscle], completedCount: Int)] = [
            (primary: [.chest], secondary: [], completedCount: 4),
            (primary: [.chest], secondary: [], completedCount: 4)
        ]
        let hit = SessionStats.musclesHit(sets: sets)
        #expect(hit[.chest] == 1.0)
    }
}
