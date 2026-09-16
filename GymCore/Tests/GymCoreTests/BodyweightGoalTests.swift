import Testing
@testable import GymCore

@Suite("BodyweightGoal")
struct BodyweightGoalTests {
    @Test("a loss goal: dropping weight is toward, gaining is away")
    func lossGoal() {
        let toward = BodyweightGoal.status(currentKg: 82.1, goalKg: 80, deltaKg: -1.4, unit: .kg)
        #expect(toward.trend == .toward)
        #expect(!toward.isReached)
        #expect(abs(toward.remainingKg - 2.1) < 0.001)

        let away = BodyweightGoal.status(currentKg: 82.1, goalKg: 80, deltaKg: 0.8, unit: .kg)
        #expect(away.trend == .away)
    }

    @Test("a gain goal: putting weight on is toward")
    func gainGoal() {
        let status = BodyweightGoal.status(currentKg: 70, goalKg: 75, deltaKg: 1.2, unit: .kg)
        #expect(status.trend == .toward)
        #expect(status.remainingKg == 5)
        #expect(BodyweightGoal.status(currentKg: 70, goalKg: 75, deltaKg: -0.5, unit: .kg).trend == .away)
    }

    @Test("no comparison reading, or a change under 0.1 kg, reads flat")
    func flatWhenNoSignal() {
        #expect(BodyweightGoal.status(currentKg: 82, goalKg: 80, deltaKg: nil, unit: .kg).trend == .flat)
        #expect(BodyweightGoal.status(currentKg: 82, goalKg: 80, deltaKg: 0.05, unit: .kg).trend == .flat)
        #expect(BodyweightGoal.status(currentKg: 82, goalKg: 80, deltaKg: -0.05, unit: .kg).trend == .flat)
    }

    @Test("reached when the remaining distance rounds away in the lifter's unit")
    func reachedRoundsInUnit() {
        // 0.1 kg rounds to the quarter-kg grid's zero.
        let kg = BodyweightGoal.status(currentKg: 80.1, goalKg: 80, deltaKg: -2, unit: .kg)
        #expect(kg.isReached)
        #expect(kg.trend == .flat, "at goal there is no direction left to move in")

        // 0.2 kg is 0.44 lb — half a pound away on the lb grid, not yet reached.
        let lb = BodyweightGoal.status(currentKg: 80.2, goalKg: 80, deltaKg: -2, unit: .lb)
        #expect(!lb.isReached)
        // …but the same 0.2 kg is a quarter-kg step in kg, also not reached.
        #expect(!BodyweightGoal.status(currentKg: 80.2, goalKg: 80, deltaKg: -2, unit: .kg).isReached)
        // Exactly on the goal, either unit.
        #expect(BodyweightGoal.status(currentKg: 80, goalKg: 80, deltaKg: nil, unit: .lb).isReached)
    }

    @Test("past the goal still reports the distance back to it")
    func overshoot() {
        let status = BodyweightGoal.status(currentKg: 78, goalKg: 80, deltaKg: -3, unit: .kg)
        #expect(!status.isReached)
        #expect(status.remainingKg == 2)
        // Below an 80 kg goal reads as a gain goal now; still losing is away from it.
        #expect(status.trend == .away)
    }
}
