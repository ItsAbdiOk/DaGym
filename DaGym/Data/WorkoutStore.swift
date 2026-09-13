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
    /// Defaults to an in-memory photo store so tests and previews need no extra setup.
    let photoContext: ModelContext

    init(context: ModelContext, photoContext: ModelContext? = nil) {
        self.context = context
        if let photoContext {
            self.photoContext = photoContext
        } else {
            // Tests/previews: keep photos in memory; the app passes a real photo context.
            let fallback = (try? ModelContainer.dagymPhotos(inMemory: true))
                .map(ModelContext.init) ?? context
            self.photoContext = fallback
        }
    }

    func savePhotos() {
        guard photoContext.hasChanges else { return }
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
