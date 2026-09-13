import Foundation
import GymCore

/// Pure, context-free conversions between SwiftData models and the UI's
/// plain value types (`DaGym/SampleData/Models.swift`). Anything that needs
/// a `ModelContext` query (best e1RM, PR counts, history lookups) lives in
/// the relevant `WorkoutStore` extension instead.
extension ExerciseInfo.LoggingStyle {
    /// The raw key stored on `ExerciseModel.loggingStyle` (distinct from the
    /// case's display-text raw value).
    var rawKey: String {
        switch self {
        case .weightReps: "weightReps"
        case .bodyweightReps: "bodyweightReps"
        case .assisted: "assisted"
        case .weightedBodyweight: "weightedBodyweight"
        case .timedHold: "timedHold"
        case .cardio: "cardio"
        }
    }
}

extension ExerciseInfo {
    init(model: ExerciseModel) {
        self.init(
            id: model.id, name: model.name, primary: model.primary, secondary: model.secondary,
            equipment: model.equipment, incrementKg: model.incrementKg, restSeconds: model.restSeconds,
            bar: model.bar, isFavorite: model.isFavorite, isCustom: model.isCustom,
            isPerSide: model.isPerSide, instructions: model.instructions, loggingStyle: model.style
        )
    }
}

extension SetEntry {
    init(model: SetLogModel) {
        self.init(
            id: model.id, kind: model.setKind, weightKg: model.weightKg, reps: model.reps,
            effort: model.rpe.map { Effort(rpe: $0) }, isDone: model.isCompleted,
            durationSeconds: model.durationSeconds, targetSeconds: nil
        )
    }
}

extension SetLogModel {
    /// Copies the mutable fields of a `SetEntry` onto this log, keeping the
    /// SwiftData identity. Used by `WorkoutStore.sync(session:)`.
    func apply(_ entry: SetEntry, order: Int) {
        self.order = order
        kind = entry.kind.rawValue
        weightKg = entry.weightKg
        reps = entry.reps
        durationSeconds = entry.durationSeconds
        rpe = entry.effort?.rpe
        isCompleted = entry.isDone
    }
}

extension WorkoutExerciseEntry {
    init(model: WorkoutExerciseModel, exercise: ExerciseInfo) {
        let sets = (model.sets ?? [])
            .sorted { $0.order < $1.order }
            .map { SetEntry(model: $0) }
        self.init(
            id: model.id, exercise: exercise, sets: sets, supersetGroup: model.supersetGroup,
            note: model.note.isEmpty ? nil : model.note, wasSubstitution: model.wasSubstitution
        )
    }
}

extension RoutineInfo {
    init(model: RoutineModel, exercises: [ExerciseInfo], setCount: Int) {
        self.init(
            id: model.id, name: model.name, exercises: exercises, setCount: setCount,
            estimatedMinutes: max(20, setCount * 3),
            progressionRule: RoutineInfo.progressionLabel(model),
            progressionDetail: RoutineInfo.progressionDetailText(model)
        )
    }

    private static func progressionLabel(_ model: RoutineModel) -> String {
        switch model.progressionRule {
        case "linear": "Linear progression"
        default: "Double progression · \(model.repRangeLow)–\(model.repRangeHigh) reps"
        }
    }

    private static func progressionDetailText(_ model: RoutineModel) -> String {
        switch model.progressionRule {
        case "linear": "Hit every rep and the weight goes up next time."
        default: "Hit the top of the rep range on every set and the weight goes up one increment."
        }
    }
}

extension WorkoutRecord {
    init(model: WorkoutModel, prCount: Int = 0) {
        let sets = (model.exercises ?? []).flatMap { $0.sets ?? [] }
        let volume = sets.filter { $0.isCompleted && $0.setKind.countsTowardStats }
            .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        let minutes: Int
        if let endedAt = model.endedAt {
            minutes = max(0, Int(endedAt.timeIntervalSince(model.startedAt) / 60))
        } else {
            minutes = 0
        }
        self.init(
            id: model.id, title: model.title, date: model.startedAt, durationMinutes: minutes,
            volumeKg: volume, sets: sets.filter(\.isCompleted).count, prCount: prCount
        )
    }
}
