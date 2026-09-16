import Foundation
import SwiftData

/// The session note on a finished workout, edited after the fact from History (OpenGym
/// parity 20). The live screen writes the same `WorkoutModel.notes` through `sync(session:)`.
extension WorkoutStore {
    /// Replaces the workout's note with `text`, trimmed; an empty string clears it. Saves
    /// through `save()`, so History and the detail screen redraw on `changeToken`. Returns
    /// false, and writes nothing, for a workout that isn't a finished main-store row: the
    /// in-progress session owns its own note (its next `sync` would overwrite this), and an
    /// imported Apple Health session lives in the local Health store with no note to edit.
    @discardableResult
    func updateWorkoutNote(id: UUID, text: String) -> Bool {
        guard let model = fetchWorkoutModel(id: id), model.endedAt != nil else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.notes != trimmed else { return true }
        model.notes = trimmed
        save()
        return true
    }
}
