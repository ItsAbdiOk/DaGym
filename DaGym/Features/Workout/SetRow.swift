import GymCore
import SwiftUI

/// One loggable set, the prototype's table row: index · kind over the previous ghost · weight
/// · reps · effort · round tick. A done row dims its numbers and fills the tick with the
/// accent. Tapping weight or reps opens the keypad; the effort cell opens the picker.
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    // MARK: Columns

    /// The table's fixed column widths, shared with `ExerciseSetRows`' header so the two line up.
    enum Column {
        static let index: CGFloat = 26
        static let weight: CGFloat = 52
        static let reps: CGFloat = 44
        static let effort: CGFloat = 40
        static let done: CGFloat = 30
    }

    private static let swipeButtonWidth: CGFloat = 52
    private static let actionsWidth = swipeButtonWidth * 4
    private var showsSteppers: Bool { preferences.showSetSteppers }
    private var weightStepKg: Double { Self.weightStepKg(incrementKg, unit: preferences.weightUnit) }

    /// What the ± steppers move weight by: the exercise's increment, snapped to the lb plate
    /// grid the same way the keypad's ± is. Raw kg here walked a lb lifter 135 → 140.5 → 146
    /// (2.5 kg is 5.51 lb) while the keypad on the same set moved by a clean 5 lb.
    static func weightStepKg(_ incrementKg: Double, unit: WeightUnit) -> Double {
        KeypadStep.kg(incrementKg, unit: unit)
    }

    private var rowContent: some View {
        HStack(spacing: showsSteppers ? DGSpace.s1 : 0) {
            indexLabel
            // The kind + ghost column is the first thing to go when type is large or the ±
            // steppers need the room: it's a hint, not a control.
            if !showsSteppers, !dynamicTypeSize.isAccessibilitySize {
                kindAndPrevious
            } else {
                Spacer(minLength: 0)
            }
            if showsSteppers {
                stepper(symbol: "minus", label: "Decrease weight") { onAdjustWeight(-weightStepKg) }
            }
            weightCell
            if showsSteppers {
                stepper(symbol: "plus", label: "Increase weight") { onAdjustWeight(weightStepKg) }
                stepper(symbol: "minus", label: "Decrease reps") { onAdjustReps(-1) }
            }
            repsCell
            if showsSteppers { stepper(symbol: "plus", label: "Increase reps") { onAdjustReps(1) } }
            if preferences.effortTrackingEnabled { effortCell }
            doneButton
        }
        .padding(.horizontal, DGSpace.s1)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .dgTile(radius: DGRadius.sm, opacity: set.isDone ? 0.5 : 0.7)
        .dgDenseType()
    }

    private var indexLabel: some View {
        Text(String(rowIndex + 1))
            .font(.system(size: 12.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(DGColor.ink3)
            .frame(width: Column.index)
            .accessibilityLabel(SetKindBadge.accessibilityLabel(kind: set.kind, index: badgeIndex))
    }

    private var weightCell: some View {
        Button(action: onTapWeight) {
            Text(preferences.formatWeight(kg: set.weightKg))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: showsSteppers ? nil : Column.weight)
                .frame(minWidth: Column.reps, minHeight: 36)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("Weight")
        .accessibilityValue(
            "\(preferences.formatWeight(kg: set.weightKg)) \(preferences.weightUnit.symbol)"
        )
    }

    private var repsCell: some View {
        Button(action: onTapReps) {
            VStack(spacing: 0) {
                Text(repsText)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isPerSide {
                    Text("per side")
                        .font(.system(size: 9))
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .frame(width: showsSteppers ? nil : Column.reps)
            .frame(minWidth: Column.reps, minHeight: 36)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel("Reps")
        .accessibilityValue(isPerSide ? "\(repsText) per side" : repsText)
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DGColor.ink2)
                .frame(width: 26, height: 26)
                .background(DGColor.ink1.opacity(0.06), in: Circle())
        }
        .buttonStyle(.dgControl)
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
                .frame(minHeight: 52)
                .background(fill)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(label)
    }

    /// AMRAP sets show "AMRAP" until a rep count has actually been logged.
    private var repsText: String {
        let isPendingAmrap = set.kind == .amrap && !set.isDone
        return isPendingAmrap ? "AMRAP" : String(set.reps)
    }

    private var previousText: String {
        guard let weight = set.previousWeightKg, let reps = set.previousReps else { return "–" }
        return "\(preferences.formatWeight(kg: weight)) × \(reps)"
    }

    /// The rating as a plain number ("8"), or "—" until one is logged; colour never travels
    /// without the picker's plain-language line, so the cell itself stays ink.
    private var effortCell: some View {
        Button(action: onTapEffort) {
            Text(set.effort?.displayValue(scale: effortScale) ?? "—")
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DGColor.ink3)
                .frame(width: Column.effort, height: 36)
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(
            set.effort.map { "Effort, \($0.displayValue(scale: effortScale))" } ?? "Effort, not set"
        )
    }

    private var doneButton: some View {
        Button(action: onToggleDone) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(set.isDone ? DGColor.inkOnCoral : .white)
                .frame(width: 21, height: 21)
                .background(set.isDone ? DGColor.coral : DGColor.ink1.opacity(0.12), in: Circle())
                .frame(width: Column.done, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgControl)
        .accessibilityIdentifier(A11yID.setRowDone(rowIndex))
        .accessibilityLabel(doneButtonLabel)
        .accessibilityAddTraits(set.isDone ? .isSelected : [])
        // The swipe tray is a drag; VoiceOver and Switch Control get the same four actions
        // from the rotor on the row's done button instead.
        .accessibilityAction(named: "Delete set", onDelete)
        .accessibilityAction(named: "Change set type") { showKindPicker = true }
        .accessibilityAction(named: "Add drop set") { onInsertBelow(.drop) }
        .accessibilityAction(named: "Add rest-pause set") { onInsertBelow(.restPause) }
    }

    private var doneButtonLabel: String {
        SetRowAccessibility.label(
            kind: set.kind,
            weight: preferences.formatWeight(kg: set.weightKg),
            reps: repsText,
            unit: preferences.weightUnit.symbol,
            done: set.isDone,
            isCurrent: isCurrent
        )
    }

    /// Done rows dim; open rows read at full ink.
    private var valueColor: Color {
        self.set.isDone ? DGColor.ink3 : DGColor.ink1
    }
}

extension SetRow {
    /// "Warm-up" over "40 × 10" — the set's kind and last session's numbers for the same slot.
    /// Tapping the kind opens the set-type picker the swipe action also reaches.
    private var kindAndPrevious: some View {
        Button { showKindPicker = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(set.kind.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(set.kind == .working ? DGColor.ink3 : set.kind.color)
                Text(previousText)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
            }
            .lineLimit(1)
            .padding(.leading, DGSpace.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
        .accessibilityLabel(SetRowAccessibility.previousLabel(
            weight: set.previousWeightKg.map { preferences.formatWeight(kg: $0) },
            reps: set.previousReps, unit: preferences.weightUnit.symbol
        ))
        .accessibilityHint("Changes the set type")
    }
}

#Preview {
    VStack(spacing: 6) {
        SetRow(
            set: SetEntry(kind: .warmup, weightKg: 40, reps: 10, effort: Effort(rpe: 6), isDone: true),
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
        SetRow(
            set: SetEntry(kind: .amrap, weightKg: 82.5, reps: 8, previousWeightKg: 82.5, previousReps: 6),
            badgeIndex: 3, rowIndex: 3, isCurrent: false, effortScale: .rpe,
            onTapWeight: {}, onTapReps: {}, onTapEffort: {}, onToggleDone: {}
        )
    }
    .padding()
    .background(DGColor.bgBase)
    .environment(Preferences())
}
