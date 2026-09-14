import Foundation
import SwiftData

/// One `HKWorkout` logged in another app (or on the Watch) that the user has imported into
/// History.
///
/// It lives in the always-local Health store (`ModelContainer.dagymHealth`), **never** the
/// CloudKit-mirrored main store: App Store Guideline 5.1.3 forbids storing HealthKit-derived data
/// in iCloud, and every field here is a verbatim copy of a HealthKit sample. Same reasoning, and
/// the same shape, as `ProgressPhotoModel` living in `ModelContainer.dagymPhotos`.
///
/// Deliberately lighter than `WorkoutModel`: Health carries no per-set detail, so an imported
/// session is a title, a start, an end and the sample's uuid. `WorkoutStore.history()` folds these
/// into the same `WorkoutRecord` list the main store's workouts produce.
@Model
final class ImportedHealthWorkoutModel {
    var id: UUID = UUID()
    /// `HKWorkout.uuid.uuidString` — the dedupe key, and what
    /// `WorkoutStore.hasWorkout(healthKitID:)` matches on.
    var healthKitID: String = ""
    var title: String = ""
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var importedAt: Date = Date()

    init(
        id: UUID = UUID(), healthKitID: String = "", title: String = "", startedAt: Date = Date(),
        endedAt: Date = Date(), importedAt: Date = Date()
    ) {
        self.id = id
        self.healthKitID = healthKitID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.importedAt = importedAt
    }
}

/// A tombstone for an `HKWorkout` the user has already said no to — either by deleting it from
/// History after importing it, or by it having been imported and removed some other way.
///
/// Without this, the next `externalStrengthWorkouts` read (an explicit Import tap, or the opt-in
/// background observer) sees the same sample again and re-adds the row the user just deleted.
/// Local-only for the same Guideline 5.1.3 reason as `ImportedHealthWorkoutModel`.
@Model
final class IgnoredHealthWorkoutModel {
    var healthKitID: String = ""
    var ignoredAt: Date = Date()

    init(healthKitID: String = "", ignoredAt: Date = Date()) {
        self.healthKitID = healthKitID
        self.ignoredAt = ignoredAt
    }
}
