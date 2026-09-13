import Testing
@testable import GymCore

@Suite("Deload detector")
struct DeloadDetectorTests {
    @Test("no triggers means no suggestion")
    func none() {
        let lifts = [
            LiftSnapshot(name: "Bench", stalls: 0, e1rmTrend: [100, 101, 102], rpeAtSameLoadTrend: [7, 7]),
            LiftSnapshot(name: "Squat", stalls: 1, e1rmTrend: [150, 151, 150])
        ]
        #expect(DeloadDetector.evaluate(lifts: lifts, hardWeeks: 2) == nil)
    }

    @Test("3+ consecutive stalls on 2+ main lifts triggers a suggestion")
    func stallsOnTwoLifts() {
        let lifts = [
            LiftSnapshot(name: "Bench", stalls: 3, e1rmTrend: [100, 100, 100]),
            LiftSnapshot(name: "Squat", stalls: 4, e1rmTrend: [150, 150, 150]),
            LiftSnapshot(name: "Row", stalls: 0, e1rmTrend: [60, 60, 60])
        ]
        let suggestion = DeloadDetector.evaluate(lifts: lifts, hardWeeks: 0)
        #expect(suggestion != nil)
        #expect(suggestion?.reason.contains("stalled") == true)
    }

    @Test("only one lift stalling doesn't trigger the multi-lift stall rule")
    func stallOnOnlyOneLiftDoesNotTrigger() {
        let lifts = [
            LiftSnapshot(name: "Bench", stalls: 5, e1rmTrend: [100, 100, 100]),
            LiftSnapshot(name: "Squat", stalls: 0, e1rmTrend: [150, 150, 150])
        ]
        #expect(DeloadDetector.evaluate(lifts: lifts, hardWeeks: 0) == nil)
    }

    @Test("e1RM down more than 5% over the last 3 sessions triggers a suggestion")
    func e1rmRegression() {
        let lifts = [LiftSnapshot(name: "Bench", stalls: 0, e1rmTrend: [100, 95, 90])]
        let suggestion = DeloadDetector.evaluate(lifts: lifts, hardWeeks: 0)
        #expect(suggestion != nil)
        #expect(suggestion?.reason.contains("Bench") == true)
    }

    @Test("a small e1RM dip under 5% doesn't trigger")
    func smallE1rmDipDoesNotTrigger() {
        let lifts = [LiftSnapshot(name: "Bench", stalls: 0, e1rmTrend: [100, 99, 98])]
        #expect(DeloadDetector.evaluate(lifts: lifts, hardWeeks: 0) == nil)
    }

    @Test("RPE at the same load rising a point or more over 2 weeks triggers a suggestion")
    func risingRPE() {
        let lifts = [
            LiftSnapshot(name: "Bench", stalls: 0, e1rmTrend: [100, 100, 100], rpeAtSameLoadTrend: [7, 8.5])
        ]
        let suggestion = DeloadDetector.evaluate(lifts: lifts, hardWeeks: 0)
        #expect(suggestion != nil)
    }

    @Test("a small RPE rise doesn't trigger")
    func smallRPERiseDoesNotTrigger() {
        let lifts = [
            LiftSnapshot(name: "Bench", stalls: 0, e1rmTrend: [100, 100, 100], rpeAtSameLoadTrend: [7, 7.2])
        ]
        #expect(DeloadDetector.evaluate(lifts: lifts, hardWeeks: 0) == nil)
    }

    @Test("5+ hard weeks without a lighter week triggers a suggestion")
    func hardWeeksTrigger() {
        let lifts = [LiftSnapshot(name: "Bench", stalls: 0, e1rmTrend: [100, 100, 100])]
        #expect(DeloadDetector.evaluate(lifts: lifts, hardWeeks: 5) != nil)
        #expect(DeloadDetector.evaluate(lifts: lifts, hardWeeks: 4) == nil)
    }

    @Test("a lift with a single session is not a hard-weeks co-signal")
    func singleSessionIsNotStalling() {
        let lifts = [LiftSnapshot(name: "Curl", stalls: 0, e1rmTrend: [40])]
        #expect(DeloadDetector.evaluate(lifts: lifts, hardWeeks: 6) == nil)
    }

    @Test("the deload plan is ~60% of sets at ~90% of load")
    func deloadPlan() {
        let plan = DeloadDetector.deloadPlan(sets: 5, load: 100)
        #expect(plan.sets == 3)
        #expect(plan.loadKg == 90)
    }
}
