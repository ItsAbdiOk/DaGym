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
    /// Milestone tiers newly earned by this workout (plan.md §6.4), empty most of the time.
    var achievements: [AchievementInfo] = []
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
    /// Notified with the freshly-ended `WorkoutModel` at the end of `finish(session:)`. Set by
    /// `HealthSyncService.bind(to:)` to write the session to Apple Health — this type stays
    /// unaware of HealthKit itself (plan.md §6.8).
    var onWorkoutFinished: ((WorkoutModel) -> Void)?
    /// A second, additive hook list for the same "workout just finished" moment — used by
    /// `TrainingNotificationScheduler` to reschedule the streak/recap notifications without
    /// touching `onWorkoutFinished`, which `HealthSyncService` already owns.
    var workoutFinishedObservers: [(WorkoutModel) -> Void] = []

    /// Progress photos live in their own local-only container (see `ModelContainer.dagymPhotos`).
    /// `nil` when that container failed to open: photo features then read as empty and refuse
    /// writes, rather than inserting `ProgressPhotoModel` into the main context (whose schema
    /// doesn't contain it — a trap, not an error).
    let photoContext: ModelContext?

    init(context: ModelContext, photoContext: ModelContext?) {
        self.context = context
        self.photoContext = photoContext
    }

    /// Tests and previews: photos in an in-memory store, no extra setup.
    convenience init(context: ModelContext) {
        let photos = (try? ModelContainer.dagymPhotos(inMemory: true)).map(ModelContext.init)
        self.init(context: context, photoContext: photos)
    }

    func savePhotos() {
        guard let photoContext, photoContext.hasChanges else { return }
        do {
            try photoContext.save()
        } catch {
            storeLogger.error("Photo store save failed: \(error.localizedDescription, privacy: .public)")
        }
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
