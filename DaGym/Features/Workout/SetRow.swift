import GymCore
import SwiftUI

/// One loggable set: badge · previous ghost · weight · reps · effort chip · done.
/// 56 pt tall. See design sheet 01_04 "core components / set row".
struct SetRow: View {
    var set: SetEntry
    var badgeIndex: Int
    var isCurrent: Bool
    var effortScale: Effort.Scale
    var isPerSide: Bool = false
    var onTapWeight: () -> Void
    var onTapReps: () -> Void
    var onTapEffort: () -> Void
    var onToggleDone: () -> Void

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            SetKindBadge(kind: set.kind, index: badgeIndex)
            previousGhost
            Button(action: onTapWeight) {
                Text(WorkoutSession.format(set.weightKg))
                    .dgMetric(DGFont.metricM)
                    .foregroundStyle(weightColor)
                    .frame(minWidth: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: onTapReps) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(repsText)
                        .dgMetric(DGFont.metricM)
                        .foregroundStyle(DGColor.ink1)
                    if isPerSide {
                        Text("per side")
                            .font(DGFont.caption)
                            .foregroundStyle(DGColor.ink4)
                    }
                }
                .frame(minWidth: 30, alignment: .leading)
            }
            .buttonStyle(.plain)
            effortChip
            Spacer(minLength: 0)
            doneButton
        }
        .padding(.horizontal, DGSpace.s3)
        .frame(height: DGTap.rowHeight)
        .background(rowFill, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: isCurrent ? 1 : 0)
        }
    }

    /// AMRAP sets show "AMRAP" until a rep count has actually been logged.
    private var repsText: String {
        let isPendingAmrap = set.kind == .amrap && !set.isDone
        return isPendingAmrap ? "AMRAP" : String(set.reps)
    }

    private var previousGhost: some View {
        Text(set.previous ?? "–")
            .font(DGFont.footnote)
            .foregroundStyle(DGColor.ink3)
            .frame(minWidth: 44, alignment: .leading)
    }

    private var effortChip: some View {
        Button(action: onTapEffort) {
            Group {
                if let effort = set.effort {
                    Text(effort.displayValue(scale: effortScale))
                        .font(DGFont.condensedLabel(13))
                        .foregroundStyle(effort.color)
                        .frame(width: 28, height: 28)
                        .background(
                            effort.color.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: DGRadius.chip, style: .continuous)
                        )
                } else {
                    RoundedRectangle(cornerRadius: DGRadius.chip, style: .continuous)
                        .strokeBorder(DGColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var doneButton: some View {
        Button(action: onToggleDone) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(set.isDone ? DGColor.success : DGColor.ink4)
                .frame(width: DGTap.done, height: DGTap.done)
                .background(
                    set.isDone ? DGColor.success.opacity(0.22) : DGColor.surface3,
                    in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                )
        }
        .buttonStyle(DGPressStyle())
    }

    private var weightColor: Color {
        if isCurrent { return DGColor.coral }
        return set.isDone ? DGColor.ink1 : DGColor.ink2
    }

    private var rowFill: Color {
        if set.isDone { return DGColor.success.opacity(0.16) }
        return DGColor.surface2
    }

    private var rowStroke: Color { DGColor.coral }
}

#Preview {
    VStack(spacing: DGSpace.s2) {
        SetRow(
            set: SetEntry(kind: .warmup, weightKg: 40, reps: 10, isDone: true, previous: nil),
            badgeIndex: 0, isCurrent: false, effortScale: .rpe,
            onTapWeight: {}, onTapReps: {}, onTapEffort: {}, onToggleDone: {}
        )
        SetRow(
            set: SetEntry(
                weightKg: 82.5, reps: 8, effort: Effort(rpe: 8), isDone: true, previous: "80 × 8"
            ),
            badgeIndex: 1, isCurrent: false, effortScale: .rpe,
            onTapWeight: {}, onTapReps: {}, onTapEffort: {}, onToggleDone: {}
        )
        SetRow(
            set: SetEntry(weightKg: 82.5, reps: 8, previous: "80 × 8"),
            badgeIndex: 2, isCurrent: true, effortScale: .rpe,
            onTapWeight: {}, onTapReps: {}, onTapEffort: {}, onToggleDone: {}
        )
    }
    .padding()
    .background(DGColor.bgBase)
}
