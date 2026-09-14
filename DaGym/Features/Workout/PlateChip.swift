import GymCore
import SwiftUI

/// "Bar 20 · 25 + 5 per side" under the on-deck card's target row, for the next open set's
/// weight. Tapping it opens the weight keypad, whose plate line shows the same load live.
struct PlateChip: View {
    var weightKg: Double
    var bar: Bar
    var action: () -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        Button(action: action) {
            HStack(spacing: DGSpace.s2) {
                Image(systemName: "circle.circle")
                    .font(.system(size: 12, weight: .bold))
                Text(text)
                    .font(DGFont.condensedLabel(12))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            .foregroundStyle(isLoadable ? DGColor.ink2 : DGColor.danger)
            .padding(.horizontal, DGSpace.s3)
            .frame(height: 32)
            .background(DGColor.surface2, in: Capsule())
            .overlay(Capsule().strokeBorder(DGColor.hairline))
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("Plates, \(text)")
    }

    private var result: PlateCalculator.Result {
        PlateCalculator.load(
            target: weightKg, bar: bar, plates: WeightUnit.plateStock(for: preferences.weightUnit)
        )
    }

    private var isLoadable: Bool {
        if case .nearest = result { return false }
        return true
    }

    private var text: String {
        Self.text(for: result, format: { preferences.formatWeight(kg: $0) })
    }

    /// The chip's copy for a plate-calculator result, with `format` rendering kg in the user's
    /// unit. Pure so the wording is testable without a view.
    static func text(for result: PlateCalculator.Result, format: (Double) -> String) -> String {
        switch result {
        case .tooLight(let bar):
            return "Bar \(format(bar.weightKg)) · below the bar"
        case .exact(let load):
            let barText = "Bar \(format(load.bar.weightKg))"
            let perSide = load.perSide.map(format).joined(separator: " + ")
            return perSide.isEmpty ? "\(barText) · bar only" : "\(barText) · \(perSide) per side"
        case .nearest(let below, let above):
            let bar = below?.bar ?? above?.bar
            let barText = bar.map { "Bar \(format($0.weightKg))" } ?? "Bar"
            let belowText = below.map { format($0.total) } ?? "–"
            let aboveText = above.map { format($0.total) } ?? "–"
            return "\(barText) · nearest \(belowText) / \(aboveText)"
        }
    }
}
