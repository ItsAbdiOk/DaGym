import Testing
@testable import GymCore

@Suite("RPE load math")
struct RPELoadTests {
    @Test("e1RM from a completed set: 100 kg x5 @ RPE 8 -> RIR 2, R 7")
    func e1RMHandComputed() {
        // e1RM = 100 * (1 + 7/30) = 123.333...
        let value = RPELoad.e1RM(weight: 100, reps: 5, rpe: 8)
        #expect(abs(value - 123.3333) < 0.01)
    }

    @Test("solving for the same reps/RPE returns the original weight")
    func roundTrip() {
        let next = RPELoad.nextLoad(fromWeightKg: 100, reps: 5, rpe: 8, targetReps: 5, targetRPE: 8)
        #expect(abs(next - 100) < 0.001)
    }

    @Test("lower target reps at the same RPE calls for more weight")
    func fewerRepsMeansMoreWeight() {
        // e1RM 123.333, target R = 3 + 2 = 5 -> 123.333 / (1 + 5/30) = 105.714...
        let next = RPELoad.nextLoad(fromWeightKg: 100, reps: 5, rpe: 8, targetReps: 3, targetRPE: 8)
        #expect(abs(next - 105.7142) < 0.01)
    }

    @Test("a harder target RPE for the same reps calls for more weight")
    func harderRPEMeansMoreWeight() {
        // target R = 5 + (10-9) = 6 -> 123.333 / (1 + 6/30) = 102.777...
        let next = RPELoad.nextLoad(fromWeightKg: 100, reps: 5, rpe: 8, targetReps: 5, targetRPE: 9)
        #expect(abs(next - 102.7777) < 0.01)
    }

    @Test("reps to failure folds RIR into the completed reps")
    func repsToFailure() {
        #expect(RPELoad.repsToFailure(reps: 5, rpe: 8) == 7)
        #expect(RPELoad.repsToFailure(reps: 8, rpe: 10) == 8)
    }
}
