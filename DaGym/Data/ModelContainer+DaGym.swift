import Foundation
import SwiftData

/// The full DaGym persistence schema, in one place so every container and
/// migration references the same list.
enum DaGymSchema {
    static let models: [any PersistentModel.Type] = [
        ExerciseModel.self,
        RoutineModel.self,
        RoutineExerciseModel.self,
        PlannedSetModel.self,
        WorkoutModel.self,
        WorkoutExerciseModel.self,
        SetLogModel.self,
        BodyMeasurementModel.self,
        PersonalRecordModel.self,
        EquipmentProfileModel.self
    ]
}

extension ModelContainer {
    /// The app's model container. `inMemory` is for tests and previews so
    /// nothing touches disk.
    static func dagym(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(DaGymSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
