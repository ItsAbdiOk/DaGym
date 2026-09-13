import GymCore
import SwiftUI

/// One loggable set: badge · previous ghost · weight · reps · effort chip · done.
/// 56 pt tall. See design sheet 01_04 "core components / set row".
struct SetRow: View {
    var set: SetEntry
    var badgeIndex: Int
    /// The set's position within its exercise (0-based). Drives
    /// `A11yID.setRowDone(_:)` for `DaGymUITests`.
    var rowIndex: Int
    var isCurrent: Bool
    var effortScale: Effort.Scale
    var isPerSide: Bool = false
    /// The exercise's loading step — what the optional ± steppers move weight by.
    var incrementKg: Double = 2.5
    var onTapWeight: () -> Void
    var onTapReps: () -> Void
    var onTapEffort: () -> Void
    var onToggleDone: () -> Void
    /// Swipe-left actions — see design: "swipe left on a row for delete / change type".
    var onDelete: () -> Void = {}
    var onChangeKind: (SetKind) -> Void = { _ in }
    /// Drop-set / rest-pause shortcuts: insert a seeded row directly below this one.
    var onInsertBelow: (SetKind) -> Void = { _ in }
    /// ± steppers (`Preferences.showSetSteppers`), deltas in kg / reps.
    var onAdjustWeight: (Double) -> Void = { _ in }
    var onAdjustReps: (Int) -> Void = { _ in }

    @State private var isSwipeOpen = false
    @State private var showKindPicker = false
    @Environment(Preferences.self) private var preferences

    var body: some View {
        SwipeToRevealRow(actionsWidth: Self.actionsWidth, isOpen: $isSwipeOpen) {
            rowContent
        } actions: {
            swipeActions
        }
        .confirmationDialog("Change set type", isPresented: $showKindPicker, titleVisibility: .visible) {
            ForEach(SetKind.allCases, id: \.self) { kind in
                Button(kind.displayName) {
                    onChangeKind(kind)
                    isSwipeOpen = false
                }
            }
        }
    }

    private static let swipeButtonWidth: CGFloat = 52
    private static let actionsWidth = swipeButtonWidth * 4
    private var showsSteppers: Bool { preferences.showSetSteppers }

    private var rowContent: some View {
        HStack(spacing: showsSteppers ? DGSpace.s2 : DGSpace.s3) {
            SetKindBadge(kind: set.kind, index: badgeIndex)
            if !showsSteppers { previousGhost }
            if showsSteppers {
                stepper(symbol: "minus", label: "Decrease weight") { onAdjustWeight(-incrementKg) }
            }
            Button(action: onTapWeight) {
                Text(preferences.formatWeight(kg: set.weightKg))
                    .dgMetric(DGFont.metricM)
                    .foregroundStyle(weightColor)
                    .frame(minWidth: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Weight")
            .accessibilityValue(
                "\(preferences.formatWeight(kg: set.weightKg)) \(preferences.weightUnit.symbol)"
            )
            if showsSteppers {
                stepper(symbol: "plus", label: "Increase weight") { onAdjustWeight(incrementKg) }
                stepper(symbol: "minus", label: "Decrease reps") { onAdjustReps(-1) }
            }
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
            .accessibilityLabel("Reps")
            .accessibilityValue(isPerSide ? "\(repsText) per side" : repsText)
            if showsSteppers { stepper(symbol: "plus", label: "Increase reps") { onAdjustReps(1) } }
            if preferences.effortTrackingEnabled { effortChip }
            Spacer(minLength: 0)
            doneButton
        }
        .padding(.horizontal, DGSpace.s3)
        .frame(minHeight: DGTap.rowHeight)
        .background(rowFill, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: isCurrent ? 1 : 0)
        }
    }

    private var swipeActions: some View {
        HStack(spacing: 0) {
            swipeButton(
                symbol: "arrow.down.right", tint: DGColor.setDrop, fill: DGColor.surface3,
                label: "Add drop set"
            ) {
                onInsertBelow(.drop)
                isSwipeOpen = false
            }
            swipeButton(
                symbol: "pause.circle", tint: DGColor.setRestPause, fill: DGColor.surface3,
                label: "Add rest-pause set"
            ) {
                onInsertBelow(.restPause)
                isSwipeOpen = false
            }
            swipeButton(
                symbol: "arrow.triangle.2.circlepath", tint: DGColor.setSuperset, fill: DGColor.surface3,
                label: "Change set type"
            ) {
                showKindPicker = true
            }
            swipeButton(
                symbol: "trash", tint: .white, fill: DGColor.danger, label: "Delete set", action: onDelete
            )
        }
    }

    private func stepper(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DGColor.ink2)
                .frame(width: 28, height: 28)
                .background(DGColor.surface3, in: Circle())
        }
        .buttonStyle(DGPressStyle())
        .accessibilityLabel(label)
    }

    private func swipeButton(
        symbol: String, tint: Color, fill: Color, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: Self.swipeButtonWidth)
                .frame(minHeight: DGTap.rowHeight)
                .background(fill)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// AMRAP sets show "AMRAP" until a rep count has actually been logged.
    private var repsText: String {
        let isPendingAmrap = set.kind == .amrap && !set.isDone
        return isPendingAmrap ? "AMRAP" : String(set.reps)
    }

    private var previousGhost: some View {
        Text(previousText)
            .font(DGFont.footnote)
            .foregroundStyle(DGColor.ink3)
            .frame(minWidth: 44, alignment: .leading)
    }

    private var previousText: String {
        guard let weight = set.previousWeightKg, let reps = set.previousReps else { return "–" }
        return "\(preferences.formatWeight(kg: weight)) × \(reps)"
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
        .accessibilityLabel(
            set.effort.map { "Effort, \($0.displayValue(scale: effortScale))" } ?? "Effort, not set"
        )
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
        .accessibilityIdentifier(A11yID.setRowDone(rowIndex))
        .accessibilityLabel(doneButtonLabel)
        .accessibilityAddTraits(set.isDone ? .isSelected : [])
    }

    private var doneButtonLabel: String {
        SetRowAccessibility.label(
            kind: set.kind,
            weight: preferences.formatWeight(kg: set.weightKg),
            reps: repsText,
            unit: preferences.weightUnit.symbol,
            done: set.isDone
        )
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
            set: SetEntry(kind: .warmup, weightKg: 40, reps: 10, isDone: true),
            badgeIndex: 0, rowIndex: 0, isCurrent: false, effortScale: .rpe,
            onTapWeight: {}, onTapReps: {}, onTapEffort: {}, onToggleDone: {}
        )
        SetRow(
            set: SetEntry(
                weightKg: 82.5, reps: 8, effort: Effort(rpe: 8), isDone: true,
                previousWeightKg: 80, previousReps: 8
            ),
            badgeIndex: 1, rowIndex: 1, isCurrent: false, effortScale: .rpe,
            onTapWeight: {}, onTapReps: {}, onTapEffort: {}, onToggleDone: {}
        )
        SetRow(
            set: SetEntry(weightKg: 82.5, reps: 8, previousWeightKg: 80, previousReps: 8),
            badgeIndex: 2, rowIndex: 2, isCurrent: true, effortScale: .rpe,
            onTapWeight: {}, onTapReps: {}, onTapEffort: {}, onToggleDone: {}
        )
    }
    .padding()
    .background(DGColor.bgBase)
    .environment(Preferences())
}
