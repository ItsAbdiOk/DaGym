import Foundation
import SwiftData

/// A derived, rebuildable cache of the best-known result per exercise/kind.
/// Never the source of truth — always recomputable from `SetLogModel`s.
@Model
final class PersonalRecordModel {
    var id = UUID()
    var exerciseID: UUID?
    /// "e1rm", "maxWeight", "maxRepsAtWeight", "volume", "longestHold", "leastAssistance".
    var kind: String = "e1rm"
    var value: Double = 0
    var weightKg: Double = 0
    var reps: Int = 0
    var date = Date()
    var workoutID: UUID?

    init(
        id: UUID = UUID(), exerciseID: UUID? = nil, kind: String = "e1rm", value: Double = 0,
        weightKg: Double = 0, reps: Int = 0, date: Date = Date(), workoutID: UUID? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.kind = kind
        self.value = value
        self.weightKg = weightKg
        self.reps = reps
        self.date = date
        self.workoutID = workoutID
    }

    enum Kind: String {
        case e1rm, maxWeight, maxRepsAtWeight, volume, longestHold, leastAssistance
    }

    var recordKind: Kind {
        get { Kind(rawValue: kind) ?? .e1rm }
        set { kind = newValue.rawValue }
    }
}
