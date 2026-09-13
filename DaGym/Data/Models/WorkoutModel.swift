import Foundation
import SwiftData

/// One training session, in progress, finished or backfilled.
@Model
final class WorkoutModel {
    var id: UUID = UUID()
    var title: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var notes: String = ""
    var isBackfilled: Bool = false
    var routineID: UUID?
    var routineName: String = ""
    var bodyweightKg: Double?
    var sourceDevice: String = "iPhone"
    /// The `HKWorkout.uuid` this session was saved as, once `HealthSyncService` has written it.
    /// Nil until then, and nil forever if Health sync is off — the presence of a value is what
    /// makes a second sync attempt a no-op (plan.md §6.8).
    var healthKitID: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExerciseModel.workout)
    var exercises: [WorkoutExerciseModel]?

    init(
        id: UUID = UUID(), title: String = "", startedAt: Date = Date(), endedAt: Date? = nil,
        notes: String = "", isBackfilled: Bool = false, routineID: UUID? = nil,
        routineName: String = "", bodyweightKg: Double? = nil, sourceDevice: String = "iPhone",
        healthKitID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.isBackfilled = isBackfilled
        self.routineID = routineID
        self.routineName = routineName
        self.bodyweightKg = bodyweightKg
        self.sourceDevice = sourceDevice
        self.healthKitID = healthKitID
    }
}
