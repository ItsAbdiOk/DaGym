import Foundation
import GymCore
import SwiftData
import os

let storeLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "store")

/// Returned by `WorkoutStore.finish(session:)`.
struct WorkoutSummary {
    var durationSeconds: Int
    var volumeKg: Double
    var setsDone: Int
    var prs: [PersonalRecordInfo]
    var musclesHit: [Muscle: Double]
}

/// The single source of truth for exercises, routines and workouts. Wraps a
/// `ModelContext` and converts to/from the plain UI value types in
/// `DaGym/SampleData/Models.swift`. See `WorkoutStore+Exercises.swift`,
/// `WorkoutStore+Workouts.swift`, `WorkoutStore+History.swift` and
/// `WorkoutStore+Routines.swift` for the rest of the public API.
@MainActor
@Observable
final class WorkoutStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            storeLogger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchExerciseModel(id: UUID) -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func fetchWorkoutModel(id: UUID) -> WorkoutModel? {
        var descriptor = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func fetchRoutineModel(id: UUID) -> RoutineModel? {
        var descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
