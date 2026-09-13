import Foundation
import GymCore
import SwiftData

/// One logged set inside a `WorkoutExerciseModel`.
@Model
final class SetLogModel {
    var id: UUID = UUID()
    var order: Int = 0
    /// `SetKind` raw value.
    var kind: String = "working"
    var weightKg: Double = 0
    var reps: Int = 0
    var durationSeconds: Int?
    var distanceMeters: Double?
    var assistanceKg: Double?
    var rpe: Double?
    var isCompleted: Bool = false
    var completedAt: Date?
    var prescriptionReason: String = ""

    /// Inverse declared on `WorkoutExerciseModel.sets`.
    var workoutExercise: WorkoutExerciseModel?

    init(
        id: UUID = UUID(), order: Int = 0, kind: String = "working", weightKg: Double = 0,
        reps: Int = 0, durationSeconds: Int? = nil, distanceMeters: Double? = nil,
        assistanceKg: Double? = nil, rpe: Double? = nil, isCompleted: Bool = false,
        completedAt: Date? = nil, prescriptionReason: String = "",
        workoutExercise: WorkoutExerciseModel? = nil
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.assistanceKg = assistanceKg
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.prescriptionReason = prescriptionReason
        self.workoutExercise = workoutExercise
    }

    var setKind: SetKind {
        get { SetKind(rawValue: kind) ?? .working }
        set { kind = newValue.rawValue }
    }
}
