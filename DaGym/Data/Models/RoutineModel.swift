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
    /// JSON-encoded `GymCore.ProgressionRule` (plan.md §6.5). Additive and CloudKit-legal;
    /// `progressionRule`/`repRangeLow`/`repRangeHigh` stay as the display fallback for routines
    /// saved before this existed — see `Mapping.swift`'s `RoutineModel.progressionRuleValue`.
    var progressionRuleJSON: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var isArchived: Bool = false
    /// The `PlanRoutine.id` this routine was created from, when it arrived via a shared
    /// `.gymplan` file (plan.md §6.8). Nil for routines built in-app. Lets `PlanShareService`
    /// recognise a re-import of the same file and skip creating a duplicate.
    var importedFromID: UUID?
    /// SF Symbol drawn on the routine's card, widget and Live Activity; `tint` is a
    /// `RoutineTint` raw value. Both default to the brand look so older rows need no migration.
    var symbolName: String = "dumbbell"
    var tint: String = "coral"

    @Relationship(deleteRule: .cascade, inverse: \RoutineExerciseModel.routine)
    var exercises: [RoutineExerciseModel]?

    init(
        id: UUID = UUID(), name: String = "", notes: String = "",
        progressionRule: String = "doubleProgression", repRangeLow: Int = 6, repRangeHigh: Int = 8,
        progressionRuleJSON: String = "",
        createdAt: Date = Date(), updatedAt: Date = Date(), sortOrder: Int = 0, isArchived: Bool = false,
        importedFromID: UUID? = nil, symbolName: String = "dumbbell", tint: String = "coral"
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.progressionRule = progressionRule
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.progressionRuleJSON = progressionRuleJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.importedFromID = importedFromID
        self.symbolName = symbolName
        self.tint = tint
    }
}
