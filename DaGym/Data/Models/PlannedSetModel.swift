import Foundation
import GymCore
import SwiftData

/// A single planned set inside a `RoutineExerciseModel`.
@Model
final class PlannedSetModel {
    var id: UUID = UUID()
    var order: Int = 0
    /// `SetKind` raw value.
    var kind: String = "working"
    var targetReps: Int?
    var targetRepsHigh: Int?
    var targetWeightKg: Double?
    var targetRPE: Double?
    var targetSeconds: Int?

    /// Inverse declared on `RoutineExerciseModel.plannedSets`.
    var routineExercise: RoutineExerciseModel?

    init(
        id: UUID = UUID(), order: Int = 0, kind: String = "working", targetReps: Int? = nil,
        targetRepsHigh: Int? = nil, targetWeightKg: Double? = nil, targetRPE: Double? = nil,
        targetSeconds: Int? = nil, routineExercise: RoutineExerciseModel? = nil
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.targetReps = targetReps
        self.targetRepsHigh = targetRepsHigh
        self.targetWeightKg = targetWeightKg
        self.targetRPE = targetRPE
        self.targetSeconds = targetSeconds
        self.routineExercise = routineExercise
    }

    var setKind: SetKind {
        get { SetKind(rawValue: kind) ?? .working }
        set { kind = newValue.rawValue }
    }
}
