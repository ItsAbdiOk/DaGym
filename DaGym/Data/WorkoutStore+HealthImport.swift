import Foundation
import SwiftData

/// Apple Health workout import (plan.md §6.8): `HKWorkout` samples logged in another app or on
/// the Watch, surfaced in History.
///
/// Every row written here lands in the always-local Health store (`WorkoutStore.healthContext`,
/// `ModelContainer.dagymHealth`), never the CloudKit-mirrored main store — App Store Guideline
/// 5.1.3 forbids storing HealthKit-derived data in iCloud. That is the same split progress photos
/// already use. It also means a `healthKitID` collision between two devices is impossible: each
/// device keeps its own local copy of what it imported, and nothing about it syncs.
extension WorkoutStore {
    /// True when this `HKWorkout.uuid.uuidString` is already accounted for: either DaGym wrote
    /// the sample itself (`WorkoutModel.healthKitID`, main store) or it has already been imported
    /// (`ImportedHealthWorkoutModel`, local Health store).
    func hasWorkout(healthKitID: String) -> Bool {
        var ours = FetchDescriptor<WorkoutModel>(
            predicate: #Predicate { $0.healthKitID == healthKitID }
        )
        ours.fetchLimit = 1
        if fetchFirst(ours) != nil { return true }
        return importedHealthWorkout(healthKitID: healthKitID) != nil
    }

    /// True when the user has already deleted (or otherwise dismissed) this `HKWorkout` — the
    /// tombstone that stops the next observer fire, or the next explicit Import tap, silently
    /// resurrecting a row the user just swiped away.
    func isIgnoredHealthWorkout(healthKitID: String) -> Bool {
        var descriptor = FetchDescriptor<IgnoredHealthWorkoutModel>(
            predicate: #Predicate { $0.healthKitID == healthKitID }
        )
        descriptor.fetchLimit = 1
        return ((try? healthContext?.fetch(descriptor))?.first) != nil
    }

    /// The single "leave this sample alone" check: already imported, already ours, or tombstoned.
    func shouldSkipHealthImport(healthKitID: String) -> Bool {
        hasWorkout(healthKitID: healthKitID) || isIgnoredHealthWorkout(healthKitID: healthKitID)
    }

    /// Inserts one `HealthExternalWorkout` into the local Health store, skipping it when
    /// `shouldSkipHealthImport` says so. Health carries no per-set detail, so an imported session
    /// is a title, a start and an end — it shows up in History next to everything else.
    @discardableResult
    func importExternalWorkout(_ external: HealthExternalWorkout) -> ImportedHealthWorkoutModel? {
        guard let healthContext, !shouldSkipHealthImport(healthKitID: external.uuid) else { return nil }
        let model = ImportedHealthWorkoutModel(
            healthKitID: external.uuid, title: external.title, startedAt: external.start,
            endedAt: external.end
        )
        healthContext.insert(model)
        saveHealth()
        return model
    }

    /// Every imported Health workout, newest first.
    func importedHealthWorkouts() -> [ImportedHealthWorkoutModel] {
        let descriptor = FetchDescriptor<ImportedHealthWorkoutModel>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? healthContext?.fetch(descriptor)) ?? []
    }

    func importedHealthWorkout(id: UUID) -> ImportedHealthWorkoutModel? {
        var descriptor = FetchDescriptor<ImportedHealthWorkoutModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? healthContext?.fetch(descriptor))?.first
    }

    func importedHealthWorkout(healthKitID: String) -> ImportedHealthWorkoutModel? {
        var descriptor = FetchDescriptor<ImportedHealthWorkoutModel>(
            predicate: #Predicate { $0.healthKitID == healthKitID }
        )
        descriptor.fetchLimit = 1
        return (try? healthContext?.fetch(descriptor))?.first
    }

    /// Deletes an imported Health workout **and writes a tombstone**, so the sample is never
    /// re-imported. Returns a snapshot for the undo toast (`restoreImportedHealthWorkout`).
    @discardableResult
    func deleteImportedHealthWorkout(id: UUID) -> ImportedHealthWorkoutSnapshot? {
        guard let healthContext, let model = importedHealthWorkout(id: id) else { return nil }
        let snapshot = ImportedHealthWorkoutSnapshot(model: model)
        healthContext.delete(model)
        if !isIgnoredHealthWorkout(healthKitID: snapshot.healthKitID) {
            healthContext.insert(IgnoredHealthWorkoutModel(healthKitID: snapshot.healthKitID))
        }
        saveHealth()
        return snapshot
    }

    /// Undo for `deleteImportedHealthWorkout`: puts the row back with the same id and lifts the
    /// tombstone, so the workout behaves exactly as it did before the swipe.
    func restoreImportedHealthWorkout(_ snapshot: ImportedHealthWorkoutSnapshot) {
        guard let healthContext, importedHealthWorkout(id: snapshot.id) == nil else { return }
        // Hoisted: `#Predicate` captures a plain local cleanly, a property of a captured struct
        // much less reliably.
        let key = snapshot.healthKitID
        let tombstones = FetchDescriptor<IgnoredHealthWorkoutModel>(
            predicate: #Predicate { $0.healthKitID == key }
        )
        ((try? healthContext.fetch(tombstones)) ?? []).forEach(healthContext.delete)
        healthContext.insert(
            ImportedHealthWorkoutModel(
                id: snapshot.id, healthKitID: snapshot.healthKitID, title: snapshot.title,
                startedAt: snapshot.startedAt, endedAt: snapshot.endedAt
            )
        )
        saveHealth()
    }

    /// One-time repair for stores written by the first Apple Health build (commit 21dd63d), which
    /// put HealthKit-derived rows straight into the CloudKit-mirrored main store: imported
    /// workouts as `WorkoutModel(sourceDevice: "Health")` and pulled weigh-ins as
    /// `BodyMeasurementModel(source: "health")`.
    ///
    /// Imported workouts are moved into the local Health store (so the user keeps them) and the
    /// Health-sourced measurements are dropped outright — the bodyweight chart reads Health live
    /// now, so nothing is lost. Returns how many rows were removed from the main store. A no-op
    /// on a store that never ran that build.
    @discardableResult
    func purgeHealthDerivedRowsFromMainStore() -> Int {
        let imported = FetchDescriptor<WorkoutModel>(
            predicate: #Predicate { $0.sourceDevice == "Health" }
        )
        let strays = fetch(imported)
        for stray in strays {
            // Deliberately NOT `hasWorkout`: the stray itself is still in the main store under
            // this id, so that check would always say "already have it" and the move would
            // silently become a delete. Only the local Health store is a real duplicate here.
            if let healthKitID = stray.healthKitID,
               importedHealthWorkout(healthKitID: healthKitID) == nil {
                healthContext?.insert(
                    ImportedHealthWorkoutModel(
                        healthKitID: healthKitID, title: stray.title, startedAt: stray.startedAt,
                        endedAt: stray.endedAt ?? stray.startedAt
                    )
                )
            }
            context.delete(stray)
        }
        let measurements = FetchDescriptor<BodyMeasurementModel>(
            predicate: #Predicate { $0.source == "health" }
        )
        let healthRows = fetch(measurements)
        healthRows.forEach(context.delete)
        let removed = strays.count + healthRows.count
        guard removed > 0 else { return 0 }
        saveHealth()
        save()
        return removed
    }
}

/// A value copy of a deleted imported Health workout, enough to put it back unchanged — the
/// Health-store equivalent of `DeletedWorkout`. Nothing is kept in any store, so it is
/// CloudKit-neutral by construction.
struct ImportedHealthWorkoutSnapshot: Sendable {
    var id: UUID
    var healthKitID: String
    var title: String
    var startedAt: Date
    var endedAt: Date

    init(model: ImportedHealthWorkoutModel) {
        id = model.id
        healthKitID = model.healthKitID
        title = model.title
        startedAt = model.startedAt
        endedAt = model.endedAt
    }
}

extension WorkoutStore {
    /// An imported Health workout as a History row (`WorkoutStore.history()` merges these in).
    /// Health carries no per-set detail, so volume, sets and PR count are all zero — only the
    /// title and the duration are real.
    static func record(imported: ImportedHealthWorkoutModel) -> WorkoutRecord {
        let seconds = max(0, imported.endedAt.timeIntervalSince(imported.startedAt))
        return WorkoutRecord(
            id: imported.id, title: imported.title, date: imported.startedAt,
            durationMinutes: Int(seconds / 60), volumeKg: 0, sets: 0, prCount: 0
        )
    }
}

extension DeletedWorkout {
    /// An imported Apple Health session, so one undo toast covers both kinds of History row —
    /// `WorkoutStore.restoreWorkout(_:)` routes on `importedHealthWorkout` being set.
    init(imported: ImportedHealthWorkoutSnapshot) {
        id = imported.id
        title = imported.title
        startedAt = imported.startedAt
        endedAt = imported.endedAt
        notes = ""
        isBackfilled = true
        routineID = nil
        routineName = ""
        bodyweightKg = nil
        sourceDevice = "Health"
        healthKitID = imported.healthKitID
        exercises = []
        importedHealthWorkout = imported
    }
}
