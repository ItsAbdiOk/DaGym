import Foundation
import GymCore
import SwiftData

/// A movement the user can log, either seeded from the built-in library or
/// created by the user. CloudKit-legal: no unique constraints, every stored
/// property defaults, every relationship optional.
@Model
final class ExerciseModel {
    var id: UUID = UUID()
    /// The JSON "id" for seeded exercises. Nil for custom exercises.
    var seedID: String?
    var name: String = ""
    var primaryMuscles: [String] = []
    var secondaryMuscles: [String] = []
    var equipment: String = "other"
    var mechanic: String?
    var loggingStyle: String = "weightReps"
    var isPerSide: Bool = false
    var isCustom: Bool = false
    var isFavorite: Bool = false
    /// "olympic", "ezBar", "womens", … or nil when the exercise has no bar.
    var barType: String?
    var incrementKg: Double = 2.5
    var restSeconds: Int = 150
    var instructions: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    /// Provenance of `instructions`/`primaryMuscles`/etc: "" (free-exercise-db,
    /// the original seed), "wger", or "" for user-created custom exercises.
    var dataSource: String = ""
    /// wger.de (or other source) permalink for this exercise, when known.
    var sourceURL: String = ""
    /// Licence covering `instructions` when sourced externally, e.g. "CC-BY-SA 4.0".
    var licence: String = ""
    /// Attribution names for `instructions`, when the source requires them.
    var authors: [String] = []
    /// Set when this row lost a `seedID` fold (`ExerciseSeeder.dedupe`): the `id` of the row
    /// that won. A merged row is a tombstone — hidden from every read, kept alive so a
    /// `WorkoutExerciseModel`/`RoutineExerciseModel`/PR row that CloudKit delivers *after* the
    /// fold still has something to link to and can be re-pointed by the next dedupe pass.
    /// Deleting the loser outright (what this replaced) nulled those late arrivals on both
    /// devices and lost the history behind them permanently.
    var mergedIntoID: UUID?
    /// When `mergedIntoID` was first stamped. A tombstone is only really deleted once it has
    /// been merged for `ExerciseSeeder.tombstoneGracePeriod` and still has no children.
    var mergedAt: Date?

    /// Inverse declared on `RoutineExerciseModel.exercise`.
    var routineExercises: [RoutineExerciseModel]?
    /// Inverse declared on `WorkoutExerciseModel.exercise`.
    var workoutExercises: [WorkoutExerciseModel]?

    init(
        id: UUID = UUID(), seedID: String? = nil, name: String = "",
        primaryMuscles: [String] = [], secondaryMuscles: [String] = [], equipment: String = "other",
        mechanic: String? = nil, loggingStyle: String = "weightReps", isPerSide: Bool = false,
        isCustom: Bool = false, isFavorite: Bool = false, barType: String? = nil,
        incrementKg: Double = 2.5, restSeconds: Int = 150, instructions: String = "",
        notes: String = "", createdAt: Date = Date(), dataSource: String = "",
        sourceURL: String = "", licence: String = "", authors: [String] = []
    ) {
        self.id = id
        self.seedID = seedID
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.mechanic = mechanic
        self.loggingStyle = loggingStyle
        self.isPerSide = isPerSide
        self.isCustom = isCustom
        self.isFavorite = isFavorite
        self.barType = barType
        self.incrementKg = incrementKg
        self.restSeconds = restSeconds
        self.instructions = instructions
        self.notes = notes
        self.createdAt = createdAt
        self.dataSource = dataSource
        self.sourceURL = sourceURL
        self.licence = licence
        self.authors = authors
    }

    /// True for a row that lost a seed fold. Every read path filters these out.
    var isMergedAway: Bool { mergedIntoID != nil }

    var primary: [Muscle] { primaryMuscles.compactMap(Muscle.init(rawValue:)) }
    var secondary: [Muscle] { secondaryMuscles.compactMap(Muscle.init(rawValue:)) }

    var style: ExerciseInfo.LoggingStyle {
        switch loggingStyle {
        case "bodyweightReps": .bodyweightReps
        case "assisted": .assisted
        case "weightedBodyweight": .weightedBodyweight
        case "timedHold": .timedHold
        case "cardio": .cardio
        default: .weightReps
        }
    }

    /// The bar this exercise loads onto, derived from `barType`.
    var bar: Bar? {
        switch barType {
        case "olympic": .olympic
        case "womens": .womens
        case "ezBar": Bar(name: "EZ Bar", weightKg: 7.5)
        default: nil
        }
    }
}
