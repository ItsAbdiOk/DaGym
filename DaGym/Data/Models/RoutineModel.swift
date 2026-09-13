import Foundation
import SwiftData

/// A reusable training plan: an ordered list of exercises with planned sets.
@Model
final class RoutineModel {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var progressionRule: String = "doubleProgression"
    var repRangeLow: Int = 6
    var repRangeHigh: Int = 8
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \RoutineExerciseModel.routine)
    var exercises: [RoutineExerciseModel]?

    init(
        id: UUID = UUID(), name: String = "", notes: String = "",
        progressionRule: String = "doubleProgression", repRangeLow: Int = 6, repRangeHigh: Int = 8,
        createdAt: Date = Date(), updatedAt: Date = Date(), sortOrder: Int = 0, isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.progressionRule = progressionRule
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }
}
