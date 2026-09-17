import GymCore
import SwiftUI

/// "Bar 20 · 25 + 5 per side" under the on-deck card's target row, for the next open set's
/// weight. Tapping it opens the weight keypad, whose plate line shows the same load live.
struct PlateChip: View {
    var weightKg: Double
    var bar: Bar
    /// The lifter's *own* rack — `WorkoutStore.activeInventory()`, fetched once by
    /// `ActiveWorkoutView` and passed down, never read from the store here: this chip sits on
    /// the on-deck card, and reading the store from `body` cost a SwiftData fetch per render
    /// (three, in fact — `result` was reached three times). `nil` falls back to the unit's
    /// standard plate set, for previews and hosts with no store.
    var inventory: ProgressionEquipment?
    var action: () -> Void

    @Environment(Preferences.self) private var preferences

    var body: some View {
        // Once per body, not once per read.
        let result = result
        let text = Self.text(for: result, format: { preferences.formatWeight(kg: $0) })
        Button(action: action) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Self.isLoadable(result) ? DGColor.ink2 : DGColor.danger)
                .padding(.horizontal, 9)
                .frame(minHeight: 24)
                .dgInkPill(radius: DGRadius.chip, opacity: 0.06)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("Plates, \(text)")
    }

    /// The chip used to assume the standard set, so it called the engine's own prescription
    /// unloadable and offered "20 + 10 per side" to someone who owns neither plate.
    /// `bar` still wins — it is this exercise's bar (an EZ bar, say).
    private var result: PlateCalculator.Result {
        var equipment = inventory ?? ProgressionEquipment(
            bar: bar, plates: WeightUnit.plateStock(for: preferences.weightUnit), collarsKg: 0
        )
        equipment.bar = bar
        return PlateCalculator.load(
            target: weightKg, bar: equipment.bar, plates: equipment.plates, collarsKg: equipment.collarsKg
        )
    }

    private static func isLoadable(_ result: PlateCalculator.Result) -> Bool {
        if case .nearest = result { return false }
        return true
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
