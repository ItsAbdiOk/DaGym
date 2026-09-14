import Foundation
import SwiftData

/// Apple Health workout import (plan.md §6.8): `HKWorkout` samples logged in another app or on
/// the Watch, surfaced in History as backfilled `WorkoutModel`s. See `HealthSyncService.
/// pullExternalWorkouts`, which is the only caller — kept as its own file (rather than folded
/// into `WorkoutStore+Workouts.swift`, already near the file-length limit) so the dedupe contract
/// stays easy to find.
extension WorkoutStore {
    /// True when some `WorkoutModel` already carries this `HKWorkout.uuid.uuidString` — either
    /// one we wrote ourselves (`HealthSyncService.syncFinishedWorkout`) or one imported before.
    /// `HealthSyncService.pullExternalWorkouts` calls this before inserting, so a workout already
    /// seen is never duplicated even across repeated background-delivery callbacks.
    func hasWorkout(healthKitID: String) -> Bool {
        var descriptor = FetchDescriptor<WorkoutModel>(
            predicate: #Predicate { $0.healthKitID == healthKitID }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor))?.first) != nil
    }

    /// Inserts one `HealthExternalWorkout` (an `HKWorkout` logged in another app or on the Watch)
    /// as a finished, backfilled `WorkoutModel`, skipping it if `hasWorkout(healthKitID:)` already
    /// knows it. Has no exercises/sets — Health doesn't carry per-set detail — so it shows up in
    /// History as a session with a title, duration and source, editable like any backfill.
    @discardableResult
    func importExternalWorkout(_ external: HealthExternalWorkout) -> WorkoutModel? {
        guard !hasWorkout(healthKitID: external.uuid) else { return nil }
        let model = WorkoutModel(
            title: external.title, startedAt: external.start, endedAt: external.end,
            isBackfilled: true, routineName: "", sourceDevice: "Health", healthKitID: external.uuid
        )
        context.insert(model)
        save()
        return model
    }
}
