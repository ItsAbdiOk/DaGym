import Foundation
import GymCore
import OSLog
import SwiftData

private let pruneLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "routine-prune")

/// The one-time clean-up for installs that predate "DaGym ships no routines": every device
/// seeded all 13 starters on first launch, and most of them were never opened. Phone-only —
/// the watch never seeds or prunes; a deletion here syncs through CloudKit like any other.
extension RoutineSeeder {
    /// Deletes every untouched starter once per device, gated on
    /// `Preferences.starterRoutinesPruned`. Runs after the seeders and the seed fold so a
    /// second device's copy has already been folded into the survivor being judged. Returns the
    /// number deleted (0 on every launch after the first).
    @discardableResult
    static func pruneUntouchedStartersOnce(store: WorkoutStore, preferences: Preferences) -> Int {
        guard !preferences.starterRoutinesPruned else { return 0 }
        let pruned = deleteUntouchedStarters(store: store)
        preferences.starterRoutinesPruned = true
        pruneLogger.info("Pruned \(pruned, privacy: .public) untouched starter routines.")
        return pruned
    }

    /// Deletes the routines `untouchedStarters` names. Also what `SampleDataSeeder.clear` uses
    /// to take back the trio it seeded, once the sample workouts that pointed at it are gone.
    @discardableResult
    static func deleteUntouchedStarters(store: WorkoutStore, among names: [String]? = nil) -> Int {
        let doomed = untouchedStarters(store: store, among: names)
        for model in doomed { store.deleteRoutine(id: model.id) }
        return doomed.count
    }

    /// A starter the lifter never made theirs: a live routine whose `importedFromID` is one of
    /// `starterIDs` (restricted to `names` when given), whose name is still the starter's, that
    /// no workout was logged against (`WorkoutModel.routineID`), that no program cycles
    /// (`ProgramModel.routineIDs`) and that the weekly schedule doesn't place — days or date
    /// overrides. Edited sets or swapped lifts do not count as touched: `routineWasEdited`'s
    /// signal is the fold's, and a lifter who tuned a starter they then never ran, scheduled or
    /// programmed can ask the coach for it back in a sentence.
    static func untouchedStarters(store: WorkoutStore, among names: [String]? = nil) -> [RoutineModel] {
        let wanted = names ?? allStarterNames
        var nameByID: [UUID: String] = [:]
        for name in wanted {
            if let id = starterIDs[name] { nameByID[id] = name }
        }
        let candidates = store.fetch(FetchDescriptor<RoutineModel>()).filter { model in
            guard !model.isMergedAway, let importedFromID = model.importedFromID,
                  let starterName = nameByID[importedFromID] else { return false }
            // An edit stamps `updatedAt` (`WorkoutStore+Routines`); a seeded row keeps both
            // dates within the same launch. Five minutes leaves room for a slow first seed.
            let edited = model.updatedAt.timeIntervalSince(model.createdAt) > 5 * 60
            return model.name == starterName && !edited
        }
        guard !candidates.isEmpty else { return [] }
        let referenced = referencedRoutineIDs(store: store)
        return candidates.filter { !referenced.contains($0.id) }
    }

    /// Every routine id a workout, a program or the schedule points at.
    private static func referencedRoutineIDs(store: WorkoutStore) -> Set<UUID> {
        var ids = Set(store.fetch(FetchDescriptor<WorkoutModel>()).compactMap(\.routineID))
        for program in store.fetch(FetchDescriptor<ProgramModel>()) {
            ids.formUnion(program.routineIDs)
        }
        let schedule = store.schedule()
        for routineIDs in schedule.dayRoutines.values { ids.formUnion(routineIDs) }
        for routineIDs in schedule.dateOverrides.values { ids.formUnion(routineIDs) }
        return ids
    }
}
