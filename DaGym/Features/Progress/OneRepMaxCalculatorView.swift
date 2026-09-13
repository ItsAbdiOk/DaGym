import GymCore
import SwiftUI

/// "What would X kg × Y reps be" — Epley/Brzycki/Wathen plus the app's mean e1RM, and a
/// percentage table rounded to the user's plate grid (plan.md §6.4). Reachable from the Progress
/// tab and from a single exercise's detail screen.
struct OneRepMaxCalculatorView: View {
    /// The exercise's own bar (an EZ bar override, say); the plate inventory and collar weight
    /// still come from `store.activeEquipment()` — see `equipment`.
    var bar: Bar

    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var weightKg: Double
    @State private var reps: Int

    private static let percentages = Array(stride(from: 95, through: 50, by: -5))
    private static let formulas: [(title: String, formula: OneRepMax.Formula)] = [
        ("Epley", .epley), ("Brzycki", .brzycki), ("Wathen", .wathen)
    ]

    init(weightKg: Double = 60, reps: Int = 5, bar: Bar = .olympic) {
        _weightKg = State(initialValue: weightKg)
        _reps = State(initialValue: reps)
        self.bar = bar
    }

    /// The plate math source for the percent table: this exercise's bar with the active
    /// equipment profile's plates/collars, so the calculator's "25 + 1.25 per side" matches what
    /// the progression engine actually rounds prescriptions to, rather than a fixed default
    /// plate set (S7(b)).
    private var equipment: ProgressionEquipment {
        var active = store.activeEquipment()
        active.bar = bar
        return active
    }

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s5) {
                    header
                    inputCard
                    if let mean {
                        resultCard(mean: mean)
                        percentTable(mean: mean)
                    } else {
                        EmptyState(
                            symbol: "function",
                            title: "Not Eligible",
                            message: "Enter a weight and 1–12 reps to estimate a one-rep max."
                        )
                    }
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, DGSpace.s8)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
        .presentationCornerRadius(DGRadius.sheet)
    }

    private var mean: Double? { OneRepMax.estimate(weight: weightKg, reps: reps) }

    private var header: some View {
        HStack {
            Text("1RM Calculator")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "xmark", size: 36) { dismiss() }
        }
    }

    private var inputCard: some View {
        VStack(spacing: DGSpace.s4) {
            WeightStepperRow(weightKg: $weightKg, preferences: preferences)
            Divider().overlay(DGColor.hairline)
            RepsStepperRow(reps: $reps)
        }
        .dgCard(padding: 0)
        .padding(.vertical, DGSpace.s1)
    }

    private func resultCard(mean: Double) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Estimated 1RM").dgLabel(DGColor.prGoldText)
            Text("\(preferences.formatWeight(kg: mean)) \(preferences.unitSymbol)")
                .dgMetric(DGFont.metricXL)
                .foregroundStyle(DGColor.prGoldText)
            HStack(spacing: DGSpace.s5) {
                ForEach(Array(Self.formulas.enumerated()), id: \.offset) { _, pair in
                    FormulaValue(
                        title: pair.title, weightKg: weightKg, reps: reps,
                        formula: pair.formula, prefs: preferences
                    )
                }
            }
        }
        .dgCard(fill: DGColor.prGold.opacity(0.08), stroke: DGColor.prGold.opacity(0.3))
    }

    private func percentTable(mean: Double) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Percent Of 1RM").dgLabel()
            VStack(spacing: 0) {
                ForEach(Self.percentages, id: \.self) { percent in
                    PercentRow(percent: percent, mean: mean, equipment: equipment, preferences: preferences)
                    if percent != Self.percentages.last {
                        Divider().overlay(DGColor.hairline)
                    }
                }
            }
            .dgCard(padding: 0)
        }
    }
}

/// One "Epley 102.5" mini-stat under the headline mean.
private struct FormulaValue: View {
    var title: String
    var weightKg: Double
    var reps: Int
    var formula: OneRepMax.Formula
    var prefs: Preferences

    var body: some View {
        VStack(spacing: 2) {
            Text(title).dgLabel()
            let value = OneRepMax.estimate(weight: weightKg, reps: reps, formula: formula) ?? 0
            Text(prefs.formatWeight(kg: value))
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One "95% · 93.0 kg · 25 + 5" row, rounded to the user's plate grid.
private struct PercentRow: View {
    var percent: Int
    var mean: Double
    var equipment: ProgressionEquipment
    var preferences: Preferences

    var body: some View {
        HStack {
            Text("\(percent)%")
                .font(DGFont.title3)
                .foregroundStyle(DGColor.ink1)
                .frame(width: 48, alignment: .leading)
            Text("\(preferences.formatWeight(kg: target)) \(preferences.unitSymbol)")
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink2)
            Spacer()
            Text(plateLabel)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: DGTap.min)
    }

    private var target: Double { mean * Double(percent) / 100 }

    private var plateLabel: String {
        let result = PlateCalculator.load(
            target: target, bar: equipment.bar, plates: equipment.plates, collarsKg: equipment.collarsKg
        )
        switch result {
        case .tooLight:
            return "Bar only"
        case .exact(let load):
            return load.perSideDescription.isEmpty ? "Bar only" : load.perSideDescription
        case .nearest(let below, _):
            return below.map { $0.perSideDescription.isEmpty ? "Bar only" : $0.perSideDescription } ?? "—"
        }
    }
}

/// Step size for the calculator's weight stepper, pulled out so it's testable without SwiftUI.
enum OneRepMaxStep {
    /// `weightKg` is bound in kg, so the step must be converted from the *display* unit rather
    /// than reusing `displayStep` (a rounding granularity) directly — that walked a 500 lb
    /// stepper off the 0.5 lb grid `formatWeight` rounds to. A round step in the lifter's own
    /// unit: 1 kg, or 5 lb.
    static func stepKg(for unit: WeightUnit) -> Double {
        switch unit {
        case .kg: return unit.displayStep * 4
        case .lb: return unit.toKg(5)
        }
    }
}

/// Unit-aware weight stepper: ± the display step, held down to repeat.
private struct WeightStepperRow: View {
    @Binding var weightKg: Double
    var preferences: Preferences

    var body: some View {
        HStack {
            Text("Weight")
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Stepper(value: $weightKg, in: 0...500, step: OneRepMaxStep.stepKg(for: preferences.weightUnit)) {
                Text("\(preferences.formatWeight(kg: weightKg)) \(preferences.unitSymbol)")
                    .dgMetric(DGFont.metricM, tracking: -0.5)
                    .foregroundStyle(DGColor.ink1)
                    .frame(minWidth: 88, alignment: .trailing)
            }
            .fixedSize()
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.vertical, DGSpace.s3)
    }
}

/// 1…12 reps stepper.
private struct RepsStepperRow: View {
    @Binding var reps: Int

    var body: some View {
        HStack {
            Text("Reps")
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Stepper(value: $reps, in: 1...12) {
                Text("\(reps)")
                    .dgMetric(DGFont.metricM, tracking: -0.5)
                    .foregroundStyle(DGColor.ink1)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .fixedSize()
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.vertical, DGSpace.s3)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        OneRepMaxCalculatorView(weightKg: 82.5, reps: 6)
            .environment(store)
            .environment(Preferences())
    }
}
