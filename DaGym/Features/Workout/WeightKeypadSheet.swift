import GymCore
import SwiftUI

/// Glass keypad sheet for logging a weight or rep count. Never the system
/// keyboard — the ± column steps by the exercise's own increment and the
/// plate line updates live. Detent-sized to ~520 pt. See mockup 10_00.
struct WeightKeypadSheet: View {
    var title: String
    @Binding var value: Double
    var step: Double
    var bar: Bar?
    var last: String?
    var unit: String = "kg"
    var onDone: () -> Void

    @State private var buffer = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DGSpace.s6) {
            Text(title).dgLabel()
            stepperRow
            metaLabel
            if let bar { PlateLine(target: value, bar: bar) }
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
            .buttonStyle(DGPressStyle())
            Spacer(minLength: DGSpace.s4)
            Text(displayValue)
                .dgMetric(DGFont.metricXL)
                .foregroundStyle(DGColor.ink1)
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
            .buttonStyle(DGPressStyle())
        }
    }

    private var metaLabel: some View {
        var parts = [unit.uppercased(), "STEP \(WorkoutSession.format(step))"]
        if let last { parts.append("LAST \(last)") }
        return Text(parts.joined(separator: " · ")).dgLabel()
    }

    private var keyGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: DGSpace.s2), count: 4)
        return VStack(spacing: DGSpace.s2) {
            LazyVGrid(columns: columns, spacing: DGSpace.s2) {
                ForEach(["1", "2", "3", "+2.5", "4", "5", "6", "-2.5", "7", "8", "9"], id: \.self) { key in
                    KeypadKey(label: key, isAccent: key.contains("2.5")) { tap(key) }
                        .accessibilityIdentifier(digitIdentifier(key) ?? key)
                }
                KeypadKey(label: "⌫", isAccent: false) { backspace() }
            }
            HStack(spacing: DGSpace.s2) {
                KeypadKey(label: ".", isAccent: false) { tap(".") }
                KeypadKey(label: "0", isAccent: false) { tap("0") }
                    .accessibilityIdentifier(A11yID.keypadKey("0"))
            }
        }
    }

    private var displayValue: String { buffer.isEmpty ? WorkoutSession.format(value) : buffer }

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
        if key == "+2.5" || key == "-2.5" {
            step(by: key == "+2.5" ? 2.5 : -2.5)
            return
        }
        if key == "." && buffer.contains(".") { return }
        buffer.append(key)
        if let parsed = Double(buffer) { value = parsed }
        Haptics.step()
    }

    private func backspace() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        value = Double(buffer) ?? 0
    }
}

private struct KeypadKey: View {
    var label: String
    var isAccent: Bool
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
        .buttonStyle(DGPressStyle())
    }
}

/// Live plate-load preview: turns danger + fires an invalid haptic when the
/// target isn't loadable with the assumed inventory.
private struct PlateLine: View {
    var target: Double
    var bar: Bar

    private var result: PlateCalculator.Result { PlateCalculator.load(target: target, bar: bar) }

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

    private var description: String {
        let barText = "Bar \(WorkoutSession.format(bar.weightKg))"
        switch result {
        case .tooLight:
            return "\(barText) · below the bar"
        case .exact(let load):
            let perSide = load.perSideDescription
            return perSide.isEmpty ? "\(barText) · bar only" : "\(barText) · \(perSide) per side"
        case .nearest(let below, let above):
            let belowText = below.map { WorkoutSession.format($0.total) } ?? "–"
            let aboveText = above.map { WorkoutSession.format($0.total) } ?? "–"
            return "\(barText) · nearest \(belowText) / \(aboveText)"
        }
    }
}

#Preview {
    @Previewable @State var value = 82.5
    Color.clear
        .sheet(isPresented: .constant(true)) {
            WeightKeypadSheet(
                title: "Weight", value: $value, step: 2.5, bar: .olympic, last: "80", onDone: {}
            )
        }
}
