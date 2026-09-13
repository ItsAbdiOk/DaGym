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
            isPerSide: model.isPerSide, instructions: model.instructions, loggingStyle: model.style,
            dataSource: model.dataSource, sourceURL: model.sourceURL, licence: model.licence,
            authors: model.authors
        )
    }
}

extension SetEntry {
    init(model: SetLogModel) {
        self.init(
            id: model.id, kind: model.setKind, weightKg: model.weightKg, reps: model.reps,
            effort: model.rpe.map { Effort(rpe: $0) }, isDone: model.isCompleted,
            durationSeconds: model.durationSeconds, targetSeconds: nil,
            prescriptionReason: model.prescriptionReason, assistanceKg: model.assistanceKg
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
        assistanceKg = entry.assistanceKg
        if !entry.prescriptionReason.isEmpty { prescriptionReason = entry.prescriptionReason }
    }
}

extension WorkoutExerciseEntry {
    init(model: WorkoutExerciseModel, exercise: ExerciseInfo) {
        let sets = (model.sets ?? [])
            .sorted { $0.order < $1.order }
            .map { SetEntry(model: $0) }
        self.init(
            id: model.id, exercise: exercise, sets: sets, supersetGroup: model.supersetGroup,
            note: model.note.isEmpty ? nil : model.note, wasSubstitution: model.wasSubstitution,
            wasPlannedDeload: model.wasPlannedDeload
        )
    }
}

extension RoutineInfo {
    init(model: RoutineModel, exercises: [ExerciseInfo], setCount: Int, exerciseSetCounts: [Int] = []) {
        self.init(
            id: model.id, name: model.name, exercises: exercises, setCount: setCount,
            estimatedMinutes: max(20, setCount * 3),
            progressionRule: RoutineInfo.progressionLabel(model),
            progressionDetail: RoutineInfo.progressionDetailText(model),
            exerciseSetCounts: exerciseSetCounts
        )
    }

    private static func progressionLabel(_ model: RoutineModel) -> String {
        if let rule = model.progressionRuleValue { return rule.displayName }
        switch model.progressionRule {
        case "linear": return "Linear progression"
        default: return "Double progression · \(model.repRangeLow)–\(model.repRangeHigh) reps"
        }
    }

    private static func progressionDetailText(_ model: RoutineModel) -> String {
        if let rule = model.progressionRuleValue { return rule.explanation }
        switch model.progressionRule {
        case "linear": return "Hit every rep and the weight goes up next time."
        default: return "Hit the top of the rep range on every set and the weight goes up one increment."
        }
    }
}

// MARK: - Progression rule / stall-state JSON coding (plan.md §6.5)

/// Opaque JSON coding for `GymCore.ProgressionRule`, stored on
/// `RoutineModel.progressionRuleJSON`/`RoutineExerciseModel.progressionRuleJSON`.
extension ProgressionRule {
    /// The rule editor's job (A8): reject a non-positive increment rather than persist a rule
    /// that can never increase (the engine holds forever with "no increment set"). Clamps up to
    /// the smallest increment the picker's own stepper allows.
    var incrementRejectingNonPositive: ProgressionRule {
        let floor = 0.5
        switch self {
        case .linear(let incrementKg):
            return .linear(incrementKg: max(incrementKg, floor))
        case .doubleProgression(let low, let high, let incrementKg):
            return .doubleProgression(low: low, high: high, incrementKg: max(incrementKg, floor))
        case .linearAMRAP(let incrementKg):
            return .linearAMRAP(incrementKg: max(incrementKg, floor))
        case .assisted(let stepKg):
            return .assisted(stepKg: max(stepKg, floor))
        case .rpeBased, .percentOfTrainingMax, .bodyweight, .timed:
            return self
        }
    }
}

enum ProgressionRuleCoding {
    static func encode(_ rule: ProgressionRule) -> String {
        guard let data = try? JSONEncoder().encode(rule) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode(_ json: String?) -> ProgressionRule? {
        guard let json, let data = json.data(using: .utf8), !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(ProgressionRule.self, from: data)
    }
}

/// A `Codable` mirror of `GymCore.StallState` (which isn't itself `Codable`), stored as JSON on
/// `RoutineExerciseModel.stallJSON`.
struct StallStateDTO: Codable {
    var consecutiveMisses: Int = 0
    var lastWeightKg: Double?
    /// Double progression's "no improvement" tracker (`StallState.lastWeakestReps`).
    var lastWeakestReps: Int?
    /// Timed rule's "what was actually asked" judging target (`StallState.lastTargetSeconds`).
    var lastTargetSeconds: Int?
    /// Percent/TM rule's once-per-cycle bump gate (`StallState.trainingMaxCycle`).
    var trainingMaxCycle: Int?

    init(
        consecutiveMisses: Int = 0, lastWeightKg: Double? = nil, lastWeakestReps: Int? = nil,
        lastTargetSeconds: Int? = nil, trainingMaxCycle: Int? = nil
    ) {
        self.consecutiveMisses = consecutiveMisses
        self.lastWeightKg = lastWeightKg
        self.lastWeakestReps = lastWeakestReps
        self.lastTargetSeconds = lastTargetSeconds
        self.trainingMaxCycle = trainingMaxCycle
    }

    init(_ state: StallState) {
        consecutiveMisses = state.consecutiveMisses
        lastWeightKg = state.lastWeightKg
        lastWeakestReps = state.lastWeakestReps
        lastTargetSeconds = state.lastTargetSeconds
        trainingMaxCycle = state.trainingMaxCycle
    }

    var stallState: StallState {
        StallState(
            consecutiveMisses: consecutiveMisses, lastWeightKg: lastWeightKg,
            lastWeakestReps: lastWeakestReps, lastTargetSeconds: lastTargetSeconds,
            trainingMaxCycle: trainingMaxCycle
        )
    }
}

extension RoutineModel {
    /// The routine-level rule, decoded from `progressionRuleJSON`. Nil for routines saved before
    /// this existed — callers fall back to `progressionRule`/`repRangeLow`/`repRangeHigh`.
    var progressionRuleValue: ProgressionRule? {
        get { ProgressionRuleCoding.decode(progressionRuleJSON) }
        set { progressionRuleJSON = newValue.map(ProgressionRuleCoding.encode) ?? "" }
    }
}

extension RoutineExerciseModel {
    /// Per-exercise override; nil defers to the routine's rule.
    var overrideRuleValue: ProgressionRule? {
        get { ProgressionRuleCoding.decode(progressionRuleJSON) }
        set { progressionRuleJSON = newValue.map(ProgressionRuleCoding.encode) }
    }

    var stallStateValue: StallState {
        get {
            guard let data = stallJSON.data(using: .utf8),
                  let dto = try? JSONDecoder().decode(StallStateDTO.self, from: data) else {
                return StallState()
            }
            return dto.stallState
        }
        set {
            let dto = StallStateDTO(newValue)
            guard let data = try? JSONEncoder().encode(dto) else { return }
            stallJSON = String(data: data, encoding: .utf8) ?? "{}"
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
