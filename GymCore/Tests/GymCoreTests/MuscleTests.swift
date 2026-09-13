import Foundation
import Testing
@testable import GymCore

@Suite("Muscle")
struct MuscleTests {
    @Test("the lower-body set is quads, hamstrings, glutes and calves")
    func lowerBodySet() {
        let lower = Set(Muscle.allCases.filter(\.isLowerBody))
        #expect(lower == [.quads, .hams, .glutes, .calves])
    }

    @Test("StallState decodes JSON written before the newer fields existed")
    func stallStateDecodesWithoutNewFields() throws {
        let json = Data(#"{"consecutiveMisses":2,"lastWeightKg":50}"#.utf8)
        let state = try JSONDecoder().decode(StallState.self, from: json)
        #expect(state.consecutiveMisses == 2)
        #expect(state.bestWeakestReps == nil)
        #expect(state.lastTargetReps == nil)
        #expect(state.lastPlanTargetReps == nil)
    }
}
