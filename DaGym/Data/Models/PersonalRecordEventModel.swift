import Foundation
import SwiftData

/// One "a record was set" moment: appended every time a finished workout beats the cached
/// best for an exercise/kind, and never updated afterwards. `PersonalRecordModel` answers
/// "what is the best?"; this answers "which workout set a record, and when?" — the count
/// History and the weekly recap show. Rebuilt alongside the cache by
/// `WorkoutStore.rebuildPersonalRecords()`.
@Model
final class PersonalRecordEventModel {
    var id: UUID = UUID()
    var exerciseID: UUID?
    var workoutID: UUID?
    /// `GymCore.PRKind` raw value — "e1rm", "maxWeight", "maxRepsAtWeight", "volume",
    /// "longestHold", "leastAssistance".
    var kind: String = "e1rm"
    var value: Double = 0
    var weightKg: Double = 0
    var reps: Int = 0
    /// The workout's `startedAt`, so date-window counts follow the training calendar.
    var date: Date = Date()

    init(
        id: UUID = UUID(), exerciseID: UUID? = nil, workoutID: UUID? = nil, kind: String = "e1rm",
        value: Double = 0, weightKg: Double = 0, reps: Int = 0, date: Date = Date()
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.workoutID = workoutID
        self.kind = kind
        self.value = value
        self.weightKg = weightKg
        self.reps = reps
        self.date = date
    }
}
