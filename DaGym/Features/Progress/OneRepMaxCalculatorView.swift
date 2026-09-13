import GymCore
import SwiftUI

/// "What would X kg × Y reps be" — Epley/Brzycki/Wathen plus the app's mean e1RM, and a
/// percentage table rounded to the user's plate grid (plan.md §6.4). Reachable from the Progress
/// tab and from a single exercise's detail screen.
struct OneRepMaxCalculatorView: View {
    var bar: Bar

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
                    PercentRow(percent: percent, mean: mean, bar: bar, preferences: preferences)
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
    var bar: Bar
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
        let plates = WeightUnit.plateStock(for: preferences.weightUnit)
        switch PlateCalculator.load(target: target, bar: bar, plates: plates) {
        case .tooLight:
            return "Bar only"
        case .exact(let load):
            return load.perSideDescription.isEmpty ? "Bar only" : load.perSideDescription
        case .nearest(let below, _):
            return below.map { $0.perSideDescription.isEmpty ? "Bar only" : $0.perSideDescription } ?? "—"
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
            Stepper(value: $weightKg, in: 0...500, step: preferences.weightUnit.displayStep * 4) {
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
    OneRepMaxCalculatorView(weightKg: 82.5, reps: 6)
        .environment(Preferences())
}
