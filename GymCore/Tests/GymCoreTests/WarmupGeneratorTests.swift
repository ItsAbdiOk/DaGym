import Testing
@testable import GymCore

@Suite("Warm-up generator")
struct WarmupGeneratorTests {
    @Test("barbell ramp: bar, 40 %, 60 %, 80 % rounded to 2.5 kg")
    func barbell() {
        let sets = WarmupGenerator.sets(workingWeightKg: 100, style: .barbell(bar: .olympic))
        #expect(sets == [
            WarmupSet(weightKg: 20, reps: 10),
            WarmupSet(weightKg: 40, reps: 5),
            WarmupSet(weightKg: 60, reps: 3),
            WarmupSet(weightKg: 80, reps: 2)
        ])
    }

    @Test("heavy day adds a 90 % single")
    func heavySingle() {
        let sets = WarmupGenerator.sets(
            workingWeightKg: 140, style: .barbell(bar: .olympic), estimatedOneRepMax: 150
        )
        #expect(sets.last == WarmupSet(weightKg: 125, reps: 1))
    }

    @Test("light working weight skips steps at or below the bar")
    func light() {
        let sets = WarmupGenerator.sets(workingWeightKg: 40, style: .barbell(bar: .olympic))
        // 40 % of 40 rounds to 15, below the bar, so it is dropped.
        #expect(sets == [
            WarmupSet(weightKg: 20, reps: 10),
            WarmupSet(weightKg: 25, reps: 3),
            WarmupSet(weightKg: 32.5, reps: 2)
        ])
    }

    @Test("working weight equal to the bar gives no warm-ups")
    func barOnly() {
        #expect(WarmupGenerator.sets(workingWeightKg: 20, style: .barbell(bar: .olympic)).isEmpty)
    }

    @Test("dumbbells: 50 % and 75 %, no empty bar")
    func dumbbell() {
        let sets = WarmupGenerator.sets(workingWeightKg: 32, style: .dumbbell, increment: 2)
        #expect(sets == [WarmupSet(weightKg: 16, reps: 8), WarmupSet(weightKg: 24, reps: 4)])
    }

    @Test("bodyweight has none")
    func bodyweight() {
        #expect(WarmupGenerator.sets(workingWeightKg: 0, style: .bodyweight).isEmpty)
    }
}
