import Foundation
import SwiftData

/// A multi-week training program: an ordered list of routines cycled per day, with
/// normal/deload/rest weeks (plan.md §6.5). Only one program is active at a time.
@Model
final class ProgramModel {
    var id: UUID = UUID()
    var name: String = ""
    var weeks: Int = 4
    var startedAt: Date?
    var completedAt: Date?
    var isActive: Bool = false
    /// JSON-encoded `[UUID]` — the routine to run each day of the cycle, in order.
    var routineIDsJSON: String = "[]"
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ProgramWeekModel.program)
    var programWeeks: [ProgramWeekModel]?

    init(
        id: UUID = UUID(), name: String = "", weeks: Int = 4, startedAt: Date? = nil,
        completedAt: Date? = nil, isActive: Bool = false, routineIDsJSON: String = "[]",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.weeks = weeks
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isActive = isActive
        self.routineIDsJSON = routineIDsJSON
        self.createdAt = createdAt
    }

    /// The ordered routine ids for the day-cycle, decoded from `routineIDsJSON`.
    var routineIDs: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: Data(routineIDsJSON.utf8))) ?? [] }
        set { routineIDsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }
}
