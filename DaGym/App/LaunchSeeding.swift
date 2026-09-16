import Foundation
import SwiftData

/// The store work every cold launch does before the first screen renders, in the one order it
/// must run in: seed (library, starters, equipment), fold, prune, one-shot repairs. `DaGymApp`
/// calls this and nothing else touches the sequence; `UpgradePathTests` runs the same function
/// over stores real past builds wrote, so what ships and what is tested cannot drift apart.
@MainActor
enum LaunchSeeding {
    static func run(store: WorkoutStore, preferences: Preferences) async {
        // A store already at the bundled seed version returns from each seeder after a count or
        // a flag read; the 1.4 MB JSON is only decoded (off the main actor) on a version bump or
        // a fresh install. The one fold pass for everything is `dedupeSeededRows()` below.
        await ExerciseSeeder.seedIfNeededAsync(context: store.context)
        RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)
        EquipmentSeeder.seedIfNeeded(store: store, unit: preferences.weightUnit)
        store.dedupeSeededRows()
        // Installs that predate "no shipped routines" still carry the 13 starters; the ones the
        // lifter never touched go, once per device. After the fold so a synced copy is judged as
        // one routine, not two.
        RoutineSeeder.pruneUntouchedStartersOnce(store: store, preferences: preferences)
        purgeHealthDerivedRowsOnce(store: store)
        store.backfillWorkoutTotalsIfNeeded()
    }

    /// One-time repair: the first Apple Health build wrote HealthKit-derived rows into the
    /// CloudKit-mirrored main store. Move/clear them — App Store Guideline 5.1.3. Gated on the
    /// seed-state row like the other seeders: it used to run its two predicate fetches on every
    /// launch, forever, for a build almost nobody still has data from.
    private static func purgeHealthDerivedRowsOnce(store: WorkoutStore) {
        let state = SeedState.row(in: store.context)
        guard !state.healthRowsPurged else { return }
        store.purgeHealthDerivedRowsFromMainStore()
        state.healthRowsPurged = true
        state.updatedAt = Date()
        store.save()
    }
}
