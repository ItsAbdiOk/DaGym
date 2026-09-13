import GymCore
import SwiftUI

/// Every `GymCore.ProgressionRule` case, for the builder's rule-kind menu.
enum RuleKind: String, CaseIterable, Identifiable {
    case linear, doubleProgression, linearAMRAP, rpeBased, trainingMax, bodyweight, assisted, timed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linear: "Linear"
        case .doubleProgression: "Double progression"
        case .linearAMRAP: "Linear + AMRAP"
        case .rpeBased: "RPE-based"
        case .trainingMax: "Percentage / training max"
        case .bodyweight: "Bodyweight"
        case .assisted: "Assisted"
        case .timed: "Timed"
        }
    }
}

/// The builder's editable form of a `ProgressionRule` — every knob the picker exposes
/// (increment, rep range, target RPE), regardless of which the selected kind actually uses.
struct RuleState: Hashable {
    var kind: RuleKind = .doubleProgression
    var incrementKg: Double = 2.5
    var repLow: Int = 6
    var repHigh: Int = 8
    var targetRPE: Double = 8
    /// The rule this state was built from, kept so knobs the picker doesn't expose (the
    /// `.percentOfTrainingMax` wave scheme, the `.bodyweight` rep ceiling/max sets, the
    /// `.timed` step) survive an edit instead of resetting to `TrainingConstants` defaults —
    /// only used when `kind` still matches the case it came from.
    private var originalRule: ProgressionRule?

    /// The rule this state builds. Cases the picker doesn't expose knobs for reuse
    /// `originalRule`'s parameters when `kind` still matches it, else fall back to
    /// `GymCore.TrainingConstants`' defaults.
    var rule: ProgressionRule {
        switch kind {
        case .linear: .linear(incrementKg: incrementKg)
        case .doubleProgression: .doubleProgression(low: repLow, high: repHigh, incrementKg: incrementKg)
        case .linearAMRAP: .linearAMRAP(incrementKg: incrementKg)
        case .rpeBased: .rpeBased(targetRPE: targetRPE)
        case .trainingMax:
            if case .percentOfTrainingMax(let scheme) = originalRule {
                .percentOfTrainingMax(scheme: scheme)
            } else {
                .percentOfTrainingMax(scheme: .classic)
            }
        case .bodyweight:
            if case .bodyweight(let repCeiling, let maxSets) = originalRule {
                .bodyweight(repCeiling: repCeiling, maxSets: maxSets)
            } else {
                .bodyweight(
                    repCeiling: TrainingConstants.bodyweightRepCeiling,
                    maxSets: TrainingConstants.bodyweightMaxSets
                )
            }
        case .assisted: .assisted(stepKg: incrementKg)
        case .timed:
            if case .timed(let stepSeconds) = originalRule {
                .timed(stepSeconds: stepSeconds)
            } else {
                .timed(stepSeconds: TrainingConstants.defaultTimedStepSeconds)
            }
        }
    }

    static func from(_ rule: ProgressionRule) -> RuleState {
        var state: RuleState = switch rule {
        case .linear(let inc): RuleState(kind: .linear, incrementKg: inc)
        case .doubleProgression(let low, let high, let inc):
            RuleState(kind: .doubleProgression, incrementKg: inc, repLow: low, repHigh: high)
        case .linearAMRAP(let inc): RuleState(kind: .linearAMRAP, incrementKg: inc)
        case .rpeBased(let rpe): RuleState(kind: .rpeBased, targetRPE: rpe)
        case .percentOfTrainingMax: RuleState(kind: .trainingMax)
        case .bodyweight: RuleState(kind: .bodyweight)
        case .assisted(let step): RuleState(kind: .assisted, incrementKg: step)
        case .timed: RuleState(kind: .timed)
        }
        state.originalRule = rule
        return state
    }
}

/// A rule-kind menu plus the steppers relevant to it (increment / rep range / target RPE) — used
/// both at routine level and for a per-exercise override (plan.md §6.5).
struct ProgressionRulePickerView: View {
    var title: String
    @Binding var state: RuleState
    var unit: WeightUnit = .kg

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(title).dgLabel()
            kindMenu
            Text(state.rule.explanation(unit: unit))
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            if usesIncrement {
                Stepper(value: $state.incrementKg, in: 0.5...25, step: incrementStepKg) {
                    Text("Increment \(unit.format(kg: state.incrementKg)) \(unit.symbol)")
                        .font(DGFont.subhead)
                }
            }
            if state.kind == .doubleProgression {
                Stepper(value: $state.repLow, in: 1...state.repHigh) {
                    Text("Low \(state.repLow) reps").font(DGFont.subhead)
                }
                Stepper(value: $state.repHigh, in: state.repLow...30) {
                    Text("High \(state.repHigh) reps").font(DGFont.subhead)
                }
            }
            if state.kind == .rpeBased {
                Stepper(value: $state.targetRPE, in: 5...10, step: 0.5) {
                    Text("Target RPE \(RuleState.formatted(state.targetRPE))").font(DGFont.subhead)
                }
            }
        }
    }

    private var usesIncrement: Bool {
        [.linear, .doubleProgression, .linearAMRAP, .assisted].contains(state.kind)
    }

    private var incrementStepKg: Double { RuleIncrementStep.stepKg(for: unit) }

    private var kindMenu: some View {
        Menu {
            ForEach(RuleKind.allCases) { kind in
                Button(kind.label) { state.kind = kind }
            }
        } label: {
            DGTag(text: state.kind.label, tint: DGColor.ink2, wash: DGColor.surface3)
        }
    }
}

extension RuleState {
    fileprivate static func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}

/// Step size for the rule picker's increment stepper, pulled out so it's testable without
/// SwiftUI. A kg lifter keeps the existing half-kg step; a lb lifter steps by a whole pound so
/// they can land on round numbers like "5 lb" instead of kg's 0.5 step (2.27 kg increments).
enum RuleIncrementStep {
    static func stepKg(for unit: WeightUnit) -> Double {
        unit == .kg ? 0.5 : unit.toKg(1)
    }
}
