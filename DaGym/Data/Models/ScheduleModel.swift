import Foundation
import SwiftData

/// The single row holding the user's `GymCore.WeeklySchedule`, encoded as
/// JSON. CloudKit-legal: no unique constraints, every stored property
/// defaults, so a fresh sync creates one row lazily. `eventIDsJSON` is a
/// separate JSON map (calendar-day key → EventKit event identifier) written
/// by `CalendarSyncService` so re-syncing stays idempotent.
@Model
final class ScheduleModel {
    var id: UUID = UUID()
    var scheduleJSON: String = "{}"
    var eventIDsJSON: String = "{}"
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(), scheduleJSON: String = "{}", eventIDsJSON: String = "{}",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.scheduleJSON = scheduleJSON
        self.eventIDsJSON = eventIDsJSON
        self.updatedAt = updatedAt
    }
}
