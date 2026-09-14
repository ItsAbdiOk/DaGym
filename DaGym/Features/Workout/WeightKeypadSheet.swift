import GymCore
import SwiftUI

/// Glass keypad sheet for logging a weight or rep count. Never the system
/// keyboard — the ± column steps by the exercise's own increment and the
/// plate line updates live. Detent-sized to ~520 pt. See mockup 10_00.
///
/// `value` is always canonical: kg when `unit` is set, raw reps when `unit`
/// is nil. Everything shown/typed converts to the user's unit at the edges.
struct WeightKeypadSheet: View {
    var title: String
    @Binding var value: Double
    var step: Double
    var bar: Bar?
    var last: String?
    /// The display unit for a weight field, or `nil` for a plain-number field (reps).
    var unit: WeightUnit?
    var onDone: () -> Void

    @State private var buffer = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(spacing: DGSpace.s6) {
            Text(title).dgLabel()
            stepperRow
            metaLabel
            if unit != nil { PlateLine(target: value, bar: bar ?? preferences.weightUnit.defaultBar) }
            keyGrid
            DGPrimaryButton(title: "Log set", symbol: "checkmark", fill: DGColor.success, height: 52) {
                onDone()
                dismiss()
            }
            .accessibilityIdentifier(A11yID.keypadLog)
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, DGSpace.s8)
        .padding(.bottom, DGSpace.s4)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
    }

    private var stepperRow: some View {
        HStack {
            Button {
                step(by: -step)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DGColor.ink1)
                    .frame(width: 44, height: 44)
                    .background(DGColor.surface3, in: Circle())
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Decrease by \(formattedStep)")
            Spacer(minLength: DGSpace.s4)
            Text(displayValue)
                .dgMetric(DGFont.metricXL)
                .foregroundStyle(DGColor.ink1)
                .accessibilityLabel("Value")
                .accessibilityValue(displayValue)
            Spacer(minLength: DGSpace.s4)
            Button {
                step(by: step)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DGColor.inkOnCoral)
                    .frame(width: 44, height: 44)
                    .background(DGColor.coral, in: Circle())
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Increase by \(formattedStep)")
        }
    }

    private var metaLabel: some View {
        var parts = [unitLabel, "STEP \(formattedStep)"]
        if let last { parts.append("LAST \(last)") }
        return Text(parts.joined(separator: " · ")).dgLabel()
    }

    private var keyGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: DGSpace.s2), count: 4)
        let keys = ["1", "2", "3", quickKeyLabel(positive: true), "4", "5", "6",
                    quickKeyLabel(positive: false), "7", "8", "9"]
        return VStack(spacing: DGSpace.s2) {
            LazyVGrid(columns: columns, spacing: DGSpace.s2) {
                ForEach(keys, id: \.self) { key in
                    KeypadKey(
                        label: key, isAccent: isQuickKey(key),
                        accessibilityLabel: keyAccessibilityLabel(key)
                    ) {
                        tap(key)
                    }
                    .accessibilityIdentifier(digitIdentifier(key) ?? key)
                }
                KeypadKey(label: "⌫", isAccent: false, accessibilityLabel: "Delete") { backspace() }
            }
            HStack(spacing: DGSpace.s2) {
                KeypadKey(label: ".", isAccent: false, accessibilityLabel: "Decimal point") { tap(".") }
                KeypadKey(label: "0", isAccent: false) { tap("0") }
                    .accessibilityIdentifier(A11yID.keypadKey("0"))
            }
        }
    }

    /// The current value formatted in the display unit (kg/lb for weight, plain for reps).
    private var displayValue: String { buffer.isEmpty ? formattedCurrent : buffer }

    private var unitLabel: String { unit?.symbol.uppercased() ?? "REPS" }

    private var formattedCurrent: String {
        guard let unit else { return WorkoutSession.format(value) }
        return unit.format(kg: value)
    }

    private var formattedStep: String {
        guard let unit else { return WorkoutSession.format(step) }
        return unit.format(kg: step)
    }

    /// The quick ± key's amount: the unit's own default increment for a weight field
    /// (2.5 kg, or 5 lb), 2.5 raw for reps — unchanged from the original quick-jump.
    private var quickStepAmount: Double { unit?.defaultIncrementKg ?? 2.5 }

    private var quickStepLabel: String {
        guard let unit else { return WorkoutSession.format(quickStepAmount) }
        return unit.format(kg: quickStepAmount)
    }

    private func quickKeyLabel(positive: Bool) -> String { "\(positive ? "+" : "-")\(quickStepLabel)" }

    private func isQuickKey(_ key: String) -> Bool { key.hasPrefix("+") || key.hasPrefix("-") }

    /// Clearer wording than the glyph for the ± quick-jump keys; `nil` (falls back to the
    /// digit itself) for a plain digit key.
    private func keyAccessibilityLabel(_ key: String) -> String? {
        guard isQuickKey(key) else { return nil }
        return key.hasPrefix("+") ? "Add \(quickStepLabel)" : "Subtract \(quickStepLabel)"
    }

    /// `A11yID.keypadKey(_:)` for a plain digit key, `nil` for the ± keys.
    private func digitIdentifier(_ key: String) -> String? {
        guard key.count == 1, key.first?.isNumber == true else { return nil }
        return A11yID.keypadKey(key)
    }

    private func step(by delta: Double) {
        value = max(0, value + delta)
        buffer = ""
        Haptics.step()
    }

    private func tap(_ key: String) {
        if isQuickKey(key) {
            step(by: key.hasPrefix("+") ? quickStepAmount : -quickStepAmount)
            return
        }
        if key == "." && buffer.contains(".") { return }
        buffer.append(key)
        if let parsed = Double(buffer) { value = canonical(parsed) }
        Haptics.step()
    }

    private func backspace() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        value = canonical(Double(buffer) ?? 0)
    }

    /// Converts a typed display-unit value back to the canonical value `value` stores.
    private func canonical(_ displayed: Double) -> Double {
        guard let unit else { return displayed }
        return unit.toKg(displayed)
    }
}

private struct KeypadKey: View {
    var label: String
    var isAccent: Bool
    /// Read by VoiceOver instead of `label` when the glyph itself isn't a clear word
    /// (e.g. "⌫" or "+2.5"). Defaults to `label`.
    var accessibilityLabel: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DGFont.condensedLabel(20))
                .foregroundStyle(isAccent ? DGColor.coralText : DGColor.ink1)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .dgGlass(.regular, radius: DGRadius.sm)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(accessibilityLabel ?? label)
    }
}

/// Live plate-load preview: turns danger + fires an invalid haptic when the
/// target isn't loadable with the assumed inventory.
private struct PlateLine: View {
    var target: Double
    var bar: Bar

    @Environment(Preferences.self) private var preferences

    private var result: PlateCalculator.Result {
        let plates = WeightUnit.plateStock(for: preferences.weightUnit)
        return PlateCalculator.load(target: target, bar: bar, plates: plates)
    }

    var body: some View {
        Text(description)
            .font(DGFont.footnote)
            .foregroundStyle(isInvalid ? DGColor.danger : DGColor.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DGSpace.s3)
            .frame(height: 40)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
            .onChange(of: isInvalid) { _, invalid in
                if invalid { Haptics.invalid() }
            }
    }

    private var isInvalid: Bool {
        if case .nearest = result { return true }
        return false
    }

    private func perSideText(_ load: PlateLoad) -> String {
        load.perSide.map { preferences.formatWeight(kg: $0) }.joined(separator: " + ")
    }

    private var description: String {
        let barText = "Bar \(preferences.formatWeight(kg: bar.weightKg))"
        switch result {
        case .tooLight:
            return "\(barText) · below the bar"
        case .exact(let load):
            let perSide = perSideText(load)
            return perSide.isEmpty ? "\(barText) · bar only" : "\(barText) · \(perSide) per side"
        case .nearest(let below, let above):
            let belowText = below.map { preferences.formatWeight(kg: $0.total) } ?? "–"
            let aboveText = above.map { preferences.formatWeight(kg: $0.total) } ?? "–"
            return "\(barText) · nearest \(belowText) / \(aboveText)"
        }
    }
}

#Preview {
    @Previewable @State var value = 82.5
    Color.clear
        .sheet(isPresented: .constant(true)) {
            WeightKeypadSheet(
                title: "Weight", value: $value, step: 2.5, bar: .olympic, last: "80", unit: .kg, onDone: {}
            )
        }
        .environment(Preferences())
}
