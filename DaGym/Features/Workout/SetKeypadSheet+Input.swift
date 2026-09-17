import GymCore
import SwiftUI

/// What `SetKeypadSheet` shows in each field, what its ± row moves by, and how typed digits
/// land on the bound values — split from the view so the sheet file stays under the type-length
/// cap and the pure pieces (`hint(for:…)`, `effort(typed:scale:)`) can be pinned in tests.
extension SetKeypadSheet {
    // MARK: Display

    var unit: WeightUnit { preferences.weightUnit }

    var weightText: String {
        field == .weight && !buffer.isEmpty ? buffer : unit.format(kg: weight)
    }

    var repsText: String {
        if field == .reps, !buffer.isEmpty { return buffer }
        // A planned AMRAP shows its label until a count is typed or logged.
        if set.kind == .amrap, !set.isDone, reps == 0 { return "AMRAP" }
        return WorkoutSession.format(reps)
    }

    var effortText: String {
        if field == .effort, !buffer.isEmpty { return buffer }
        return effort?.displayValue(scale: effortScale) ?? "—"
    }

    /// The plate load for the weight as typed, with the chip's wording; nil for an exercise
    /// with no bar (dumbbells, machines, bodyweight).
    var plateText: (text: String, isLoadable: Bool)? {
        guard let bar = exercise.bar, !exercise.isPerSide else { return nil }
        var equipment = inventory ?? ProgressionEquipment(
            bar: bar, plates: WeightUnit.plateStock(for: unit), collarsKg: 0
        )
        equipment.bar = bar
        let result = PlateCalculator.load(
            target: weight, bar: equipment.bar, plates: equipment.plates, collarsKg: equipment.collarsKg
        )
        let loadable: Bool
        if case .nearest = result { loadable = false } else { loadable = true }
        return (PlateChip.text(for: result, format: { preferences.formatWeight(kg: $0) }), loadable)
    }

    /// One sentence under the fields, for the selected one.
    var hint: String {
        Self.hint(
            for: field,
            context: HintContext(
                exercise: exercise, set: set, effort: effort, scale: effortScale,
                format: { preferences.formatWeight(kg: $0) }
            )
        )
    }

    /// Everything the hint sentence reads, so the pure `hint(for:context:)` stays testable.
    struct HintContext {
        var exercise: ExerciseInfo
        var set: SetEntry
        var effort: Effort?
        var scale: Effort.Scale
        var format: (Double) -> String
    }

    /// Pure so the wording is testable without a view.
    static func hint(for field: Field, context: HintContext) -> String {
        let exercise = context.exercise
        let set = context.set
        let scale = context.scale
        var previous: String?
        if let lastWeight = set.previousWeightKg, let lastReps = set.previousReps {
            previous = "Last time \(context.format(lastWeight)) × \(lastReps)."
        }
        switch field {
        case .weight:
            if exercise.bar != nil, !exercise.isPerSide { return "Plate maths updates as you type." }
            if exercise.isPerSide { return "Per side — enter the weight in one hand." }
            return previous ?? "Weight for this set."
        case .reps:
            if set.kind == .amrap { return "AMRAP — log every rep you got." }
            return previous ?? "Reps for this set."
        case .effort:
            guard let effort = context.effort else {
                return scale == .rpe
                    ? "Optional. RPE 8 means two reps left in the tank."
                    : "Optional. RIR 2 means two reps left in the tank."
            }
            let name = scale == .rpe ? "RPE" : "RIR"
            return "\(name) \(effort.displayValue(scale: scale)) — \(effort.plainLanguage)."
        }
    }

    // MARK: Steps

    var stepAmount: Double {
        switch field {
        case .weight: KeypadStep.kg(exercise.incrementKg, unit: unit)
        case .reps: 1
        case .effort: effortScale == .rpe ? 0.5 : 1
        }
    }

    var stepLabel: String {
        field == .weight ? unit.format(kg: stepAmount) : WorkoutSession.format(stepAmount)
    }

    func step(by delta: Double) {
        buffer = ""
        switch field {
        case .weight: weight = max(0, weight + delta)
        case .reps: reps = max(0, reps + delta)
        case .effort:
            // From nothing, the first tap lands on RPE 8 — the most common working rating.
            let rpe = effort?.rpe ?? 8
            let next = effortScale == .rpe ? rpe + delta : rpe - delta
            effort = Effort(rpe: next)
        }
        Haptics.step()
    }

    // MARK: Typing

    func tap(_ key: String) {
        if key == "." {
            // Reps are whole numbers; effort halves only make sense on the RPE scale.
            guard field == .weight || (field == .effort && effortScale == .rpe) else { return }
            guard !buffer.contains(".") else { return }
        }
        guard buffer.count < 6 else { return }
        buffer.append(key)
        commit()
        Haptics.step()
    }

    func backspace() {
        guard !buffer.isEmpty else {
            if field == .effort { effort = nil }
            return
        }
        buffer.removeLast()
        commit()
    }

    /// Writes the buffer through to the bound value. An effort outside the scale (a "1" on the
    /// way to "10") stays in the buffer until it reads as a rating.
    func commit() {
        let typed = Double(buffer) ?? 0
        switch field {
        case .weight: weight = unit.toKg(typed)
        case .reps: reps = typed.isFinite ? typed.rounded(.down) : 0
        case .effort:
            if buffer.isEmpty {
                effort = nil
            } else if let parsed = Self.effort(typed: typed, scale: effortScale) {
                effort = parsed
            }
        }
    }

    /// A typed number as a rating, or nil while it is not one yet: RPE 5…10, RIR 0…5.
    static func effort(typed: Double, scale: Effort.Scale) -> Effort? {
        guard typed.isFinite else { return nil }
        switch scale {
        case .rpe: return (Effort.minimumRPE...10).contains(typed) ? Effort(rpe: typed) : nil
        case .rir: return (0...5).contains(typed) ? Effort(rir: Int(typed)) : nil
        }
    }
}
