import Foundation
import Testing

@testable import GymCore

/// The secondary-mover weight used to exist in four places with two different values (0.45 in
/// the body-map thumbnail, 0.5 in stats, charts and fatigue), which made the same exercise's
/// secondary muscle read two colour steps darker on a routine card than on its own library row.
@Suite("Secondary mover share")
struct SecondaryMoverShareTests {
    @Test("every consumer reads the same constant")
    func oneWeightEverywhere() {
        #expect(Recovery.secondaryShare == SessionStats.secondaryMuscleShare)
    }

    /// The body map buckets a hit intensity with `Int((value * 3).rounded())` into four coral
    /// steps. A secondary mover must land on step 1 — the lightest tinted one — not on step 2,
    /// which reads as very nearly a primary mover.
    @Test("the weight lands on the lightest tinted body-map step, not a near-primary one")
    func weightSitsOnTheLightStep() {
        let step = Int((SessionStats.secondaryMuscleShare * 3).rounded())
        #expect(step == 1)
        #expect(Int((1.0 * 3).rounded()) == 3)
    }

    @Test("a muscle listed as both primary and secondary counts once, as a primary")
    func primaryWinsInMusclesHit() {
        let hit = SessionStats.musclesHit(
            sets: [(primary: [.biceps], secondary: [.biceps, .forearms], completedCount: 4)]
        )
        #expect(hit[.biceps] == 1.0)
        #expect(hit[.forearms] == SessionStats.secondaryMuscleShare)
    }

    @Test("setsPerMuscle does not double-count a duplicated muscle at 1.5 sets per set")
    func primaryWinsInSetsPerMuscle() {
        let now = Date()
        let sets = [PerformedSet(kind: .working, weightKg: 40, reps: 8, date: now)]
        let entry = BodyWorkout.MuscleEntry(primary: [.biceps], secondary: [.biceps], sets: sets)
        let workout = BodyWorkout(date: now, durationSeconds: 1800, entries: [entry])
        let totals = BodySeries.setsPerMuscle(
            workouts: [workout], days: 7, now: now, calendar: .current
        )
        #expect(totals[.biceps] == 1.0)
    }
}
