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

    /// The rule this state builds, filling the cases this picker doesn't expose knobs for
    /// (bodyweight/timed) with `GymCore.TrainingConstants`' defaults.
    var rule: ProgressionRule {
        switch kind {
        case .linear: .linear(incrementKg: incrementKg)
        case .doubleProgression: .doubleProgression(low: repLow, high: repHigh, incrementKg: incrementKg)
        case .linearAMRAP: .linearAMRAP(incrementKg: incrementKg)
        case .rpeBased: .rpeBased(targetRPE: targetRPE)
        case .trainingMax: .percentOfTrainingMax(scheme: .classic)
        case .bodyweight: .bodyweight(
            repCeiling: TrainingConstants.bodyweightRepCeiling, maxSets: TrainingConstants.bodyweightMaxSets
        )
        case .assisted: .assisted(stepKg: incrementKg)
        case .timed: .timed(stepSeconds: TrainingConstants.defaultTimedStepSeconds)
        }
    }

    static func from(_ rule: ProgressionRule) -> RuleState {
        return switch rule {
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
    }
}

/// A rule-kind menu plus the steppers relevant to it (increment / rep range / target RPE) — used
/// both at routine level and for a per-exercise override (plan.md §6.5).
struct ProgressionRulePickerView: View {
    var title: String
    @Binding var state: RuleState

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(title).dgLabel()
            kindMenu
            Text(state.rule.explanation())
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            if usesIncrement {
                Stepper(value: $state.incrementKg, in: 0.5...25, step: 0.5) {
                    Text("Increment \(RuleState.formatted(state.incrementKg)) kg").font(DGFont.subhead)
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
