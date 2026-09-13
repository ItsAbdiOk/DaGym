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

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExerciseModel.workout)
    var exercises: [WorkoutExerciseModel]?

    init(
        id: UUID = UUID(), title: String = "", startedAt: Date = Date(), endedAt: Date? = nil,
        notes: String = "", isBackfilled: Bool = false, routineID: UUID? = nil,
        routineName: String = "", bodyweightKg: Double? = nil, sourceDevice: String = "iPhone"
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
    }
}
