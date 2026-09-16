import Foundation
import SwiftData

extension WorkoutStore {
    /// Brings the store up to date with rows another context saved into the same container —
    /// `ImportActor`'s batched CSV import or backup restore. The same tail `dedupeSeededRows()`
    /// runs after a CloudKit merge, for the same reason: the rows are already on disk, but
    /// nothing here saved them, so the denormalised `volumeKg`/`setsDone` totals are unstamped,
    /// the PR cache doesn't know the new history, the cached catalogue is stale and no token
    /// has bumped to redraw History, Home and Library.
    ///
    /// `rebuildRecords` is the caller's "did any workouts land" — the PR rebuild replays every
    /// finished workout and is skipped when only exercises or routines came in.
    func absorbExternalImport(rebuildRecords: Bool) {
        if rebuildRecords {
            // Stamped after the actor's save: the imported rows are linked through their
            // inverses, which SwiftData populates on save — stamping earlier reads them as empty.
            restampWorkoutTotalsAfterRemoteChange()
            rebuildPersonalRecords()
        }
        if context.hasChanges { save() }
        invalidateExerciseCatalogue()
        noteExternalSave()
    }
}
