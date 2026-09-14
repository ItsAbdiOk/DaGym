import GymCore
import SwiftUI

/// "How hard was it?" — picking a rating also completes the set: one tap,
/// not two. Colour never travels without the plain-language sentence.
/// See mockup 10_00 (right).
struct EffortPickerSheet: View {
    @Binding var scale: Effort.Scale
    var onPick: (Effort) -> Void

    @State private var selected: Effort?
    @Environment(\.dismiss) private var dismiss

    private var steps: [Effort] { Effort.steps.filter { $0.rpe >= 6 } }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            Text("How hard was it?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            scaleToggle
            VStack(spacing: DGSpace.s2) {
                ForEach(steps, id: \.rpe) { effort in
                    EffortRow(
                        effort: effort, scale: scale, isSelected: selected == effort,
                        action: { selected = effort }
                    )
                }
            }
            DGPrimaryButton(
                title: "Save & start rest", symbol: "checkmark", fill: DGColor.success, height: 52
            ) {
                if let selected {
                    onPick(selected)
                    dismiss()
                }
            }
            .opacity(selected == nil ? 0.5 : 1)
            .disabled(selected == nil)
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, DGSpace.s5)
        .padding(.bottom, DGSpace.s4)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
    }

    private var scaleToggle: some View {
        HStack(spacing: 0) {
            ForEach([Effort.Scale.rpe, .rir], id: \.self) { option in
                let on = scale == option
                Button {
                    scale = option
                } label: {
                    Text(option == .rpe ? "RPE" : "RIR")
                        .font(DGFont.condensedLabel(13))
                        .foregroundStyle(on ? DGColor.inkOnCoral : DGColor.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background { if on { Capsule().fill(DGColor.coral) } }
                }
                .buttonStyle(.dgControl)
                .dgTapTarget()
            }
        }
        .padding(4)
        .background(DGColor.surface2, in: Capsule())
    }
}

private struct EffortRow: View {
    var effort: Effort
    var scale: Effort.Scale
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DGSpace.s3) {
                Text(effort.displayValue(scale: scale))
                    .dgMetric(DGFont.metricM)
                    .foregroundStyle(effort.color)
                    .frame(width: 28, alignment: .leading)
                Text(effort.plainLanguage)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink2)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(effort.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DGSpace.s4)
            .frame(height: 52)
            .background(
                effort.color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                    .strokeBorder(isSelected ? effort.color : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.dgRow)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var scale = Effort.Scale.rpe
    Color.clear
        .sheet(isPresented: .constant(true)) {
            EffortPickerSheet(scale: $scale, onPick: { _ in })
        }
}
