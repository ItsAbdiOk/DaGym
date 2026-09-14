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

@Suite("Warm-up generator: grid and logging style")
struct WarmupGeneratorGridTests {
    /// A rack with 25/20/15/10/5/2.5 but no 1.25s: 42.5 and 62.5 cannot be loaded.
    static let noMicroPlates = [
        PlateStock(weightKg: 25, count: 4), PlateStock(weightKg: 20, count: 4),
        PlateStock(weightKg: 15, count: 2), PlateStock(weightKg: 10, count: 4),
        PlateStock(weightKg: 5, count: 4), PlateStock(weightKg: 2.5, count: 4)
    ]

    @Test("every warm-up lands on a weight the rack can actually load")
    func onThePlateGrid() {
        let grid = LoadGrid.plates(bar: .olympic, plates: Self.noMicroPlates, collarsKg: 0)
        let sets = WarmupGenerator.sets(
            workingWeightKg: 105, style: .barbell(bar: .olympic), increment: 2.5, grid: grid
        )
        #expect(!sets.isEmpty)
        for set in sets {
            let loaded = PlateCalculator.load(
                target: set.weightKg, bar: .olympic, plates: Self.noMicroPlates
            )
            guard case .exact = loaded else {
                Issue.record("warm-up at \(set.weightKg) kg cannot be loaded")
                continue
            }
        }
        // Rounding to the bare 2.5 kg increment asked for 42.5 and 62.5, neither of which this
        // rack can build (both need a 1.25 pair).
        #expect(!sets.map(\.weightKg).contains(42.5))
        #expect(!sets.map(\.weightKg).contains(62.5))
    }

    @Test("assisted work gets no ramp: ramping assistance makes warm-ups harder")
    func assisted() {
        // 40 %/60 %/80 % of 30 kg of assistance is 12/18/24 kg — less help than the working
        // set, i.e. three warm-ups harder than the work itself.
        #expect(WarmupGenerator.sets(workingWeightKg: 30, style: .assisted).isEmpty)
    }

    @Test("timed holds and cardio get no rep-based ramp")
    func timed() {
        #expect(WarmupGenerator.sets(workingWeightKg: 40, style: .timed).isEmpty)
    }

    @Test("no grid keeps the old increment rounding")
    func fallsBackToIncrement() {
        let sets = WarmupGenerator.sets(workingWeightKg: 100, style: .barbell(bar: .olympic))
        #expect(sets.map(\.weightKg) == [20, 40, 60, 80])
    }
}
