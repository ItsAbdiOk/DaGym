import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Store parity: mapping")
struct ParityStoreMappingTests {
    @Test("stall state round-trips every field through the routine exercise's JSON")
    func stallStateRoundTrip() throws {
        let context = try makeContext()
        let routineExercise = RoutineExerciseModel()
        context.insert(routineExercise)

        let state = StallState(
            consecutiveMisses: 2, lastWeightKg: 80, lastWeakestReps: 7, bestWeakestReps: 9,
            lastTargetSeconds: 45, lastPlanTargetSeconds: 40, lastTargetReps: 12, lastPlanTargetReps: 10,
            trainingMaxCycle: 3
        )
        routineExercise.stallStateValue = state
        #expect(routineExercise.stallStateValue == state)
    }

    @Test("stall JSON saved before the new fields existed reads them as nil")
    func stallStateMissingFieldsAreNil() throws {
        let context = try makeContext()
        let routineExercise = RoutineExerciseModel(stallJSON: #"{"consecutiveMisses":1,"lastWeightKg":60}"#)
        context.insert(routineExercise)

        let state = routineExercise.stallStateValue
        #expect(state.consecutiveMisses == 1)
        #expect(state.lastWeightKg == 60)
        #expect(state.bestWeakestReps == nil)
        #expect(state.lastTargetReps == nil)
    }

    @Test("training-max increment follows Muscle.isLowerBody")
    func trainingMaxIncrementByBodyHalf() throws {
        let store = try makeStore()
        let squat = ExerciseInfo(name: "Squat", primary: [.quads], equipment: "barbell")
        let press = ExerciseInfo(name: "Press", primary: [.delts], equipment: "barbell")
        #expect(store.trainingMaxIncrementKg(for: squat) == TrainingConstants.trainingMaxLowerIncrementKg)
        #expect(store.trainingMaxIncrementKg(for: press) == TrainingConstants.trainingMaxUpperIncrementKg)
    }
}
