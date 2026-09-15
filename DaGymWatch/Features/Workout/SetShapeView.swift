import GymCore
import SwiftUI

/// The middle block of an exercise page: the stepper row for the current set's shape plus its
/// one-line note ("2 over target · e1RM 120 kg", "Less assistance is progress"…).
struct SetShapeView: View {
    @Environment(WatchStore.self) private var store
    var entry: WorkoutExerciseEntry
    var set: SetEntry
    var shape: SetShape
    @Binding var focus: CrownField?
    var unit: WeightUnit
    var onFocus: (CrownField) -> Void
    var onAdjust: (CrownField, AccessibilityAdjustmentDirection) -> Void
    var onEffortTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            switch shape {
            case .standard: weightedRow(hollow: false, wideReps: false)
            case .warmup: weightedRow(hollow: true, wideReps: false)
            case .amrap: weightedRow(hollow: false, wideReps: true)
            case .bodyweight: bodyweightRow
            case .assisted: assistedRow
            case .perSide: perSideRow
            case .timedHold, .cardio:
                TimedSetView(
                    entry: entry, set: set, shape: shape, focus: $focus, unit: unit, onFocus: onFocus,
                    onAdjust: onAdjust
                )
            }
            noteLine
        }
        .padding(.top, 2)
    }

    // MARK: - Rows

    private func weightedRow(hollow: Bool, wideReps: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                weightCard(hollow: hollow).layoutPriority(wideReps ? 0 : 1)
                    .frame(maxWidth: wideReps ? 70 : .infinity)
                repsCard(hollow: hollow, label: "reps").layoutPriority(wideReps ? 1 : 0)
                    .frame(maxWidth: wideReps ? .infinity : 70)
            }
            if !hollow, shape != .amrap { effortRow }
        }
    }

    private var bodyweightRow: some View {
        VStack(spacing: 6) {
            StepperCard(
                value: "\(set.reps)", label: "reps", field: .reps, focus: focus, tall: true, valueSize: 50,
                accessibilityName: "Reps", accessibilityValue: spoken(.reps, Double(set.reps)),
                onTap: { onFocus(.reps) }, onAdjust: { onAdjust(.reps, $0) }
            )
            Button("Add weight") {
                let step = SetFormat.weightStep(for: entry.exercise, unit: unit)
                store.updateSet(exerciseID: entry.id) { $0.weightKg = unit.toKg(step) }
                onFocus(.weight)
            }
            .font(WatchMetric.isSmall ? WatchFont.secondary : WatchFont.body)
            .foregroundStyle(WatchColor.accent)
            .buttonStyle(.plain)
            .frame(height: WatchMetric.isSmall ? 16 : 20)
        }
    }

    private var assistedRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                // An assisted row edits `weightKg` as the assistance dialled in — the phone's
                // convention (`WorkoutStore.assistanceKg(_:style:)`); `assistanceKg` is only the rx.
                let assistanceKg = WorkoutStore.assistanceKg(set, style: .assisted) ?? 0
                let assistance = SetFormat.weight(assistanceKg, unit: unit)
                StepperCard(
                    value: "−\(assistance)", label: "assist \(unit.symbol)", field: .assistance, focus: focus,
                    accessibilityName: "Assistance", accessibilityValue: spoken(.assistance, assistanceKg),
                    onTap: { onFocus(.assistance) }, onAdjust: { onAdjust(.assistance, $0) }
                )
                repsCard(hollow: false, label: "reps").frame(maxWidth: 70)
            }
            effortRow
        }
    }

    private var perSideRow: some View {
        VStack(spacing: 6) {
            SidePill(isLeft: !store.hasLoggedLeft(exerciseID: entry.id))
            HStack(spacing: 6) {
                weightCard(hollow: false)
                StepperCard(
                    value: "\(set.reps / 2)", label: "per side", field: .reps, focus: focus,
                    accessibilityName: "Reps",
                    accessibilityValue: spoken(.reps, Double(set.reps / 2), perSide: true),
                    onTap: { onFocus(.reps) }, onAdjust: { onAdjust(.reps, $0) }
                )
                .frame(maxWidth: 74)
            }
        }
    }

    private func weightCard(hollow: Bool) -> some View {
        StepperCard(
            value: SetFormat.weight(set.weightKg, unit: unit), label: unit.symbol, field: .weight,
            focus: focus, hollow: hollow, accessibilityName: "Weight",
            accessibilityValue: spoken(.weight, set.weightKg),
            onTap: { onFocus(.weight) }, onAdjust: { onAdjust(.weight, $0) }
        )
    }

    private func repsCard(hollow: Bool, label: String) -> some View {
        StepperCard(
            value: "\(set.reps)", label: label, field: .reps, focus: focus, hollow: hollow,
            accessibilityName: "Reps", accessibilityValue: spoken(.reps, Double(set.reps)),
            onTap: { onFocus(.reps) }, onAdjust: { onAdjust(.reps, $0) }
        )
    }

    /// "100 kilograms" — kg in, the lifter's unit out.
    private func spoken(_ field: CrownField, _ value: Double, perSide: Bool = false) -> String {
        WatchAccessibility.stepperValue(field: field, value: value, unit: unit, perSide: perSide)
    }

    /// The RPE row. Crown-focusable on the 45 mm; on 41 mm / 40 mm it drops to a plain
    /// tap-through line that opens the picker.
    @ViewBuilder private var effortRow: some View {
        if WatchMetric.isSmall {
            Button(action: onEffortTap) {
                Text("RPE \(set.effort.map { $0.displayValue(scale: .rpe) } ?? "–")")
                    .font(WatchFont.secondary)
                    .foregroundStyle(WatchColor.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("RPE")
        } else {
            effortCard
        }
    }

    private var effortCard: some View {
        Button(action: onEffortTap) {
            HStack {
                Text("RPE").font(WatchFont.body).foregroundStyle(WatchColor.inkSecondary)
                Spacer()
                Text(set.effort.map { $0.displayValue(scale: .rpe) } ?? "–")
                    .font(WatchFont.bodyMedium)
                    .foregroundStyle(WatchColor.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 10).fill(WatchColor.card))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        focus == .effort ? WatchColor.accent : .clear, lineWidth: WatchMetric.crownFocusBorder
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("RPE")
        .accessibilityValue(set.effort.map { $0.displayValue(scale: .rpe) } ?? "not set")
    }

    // MARK: - Note

    @ViewBuilder private var noteLine: some View {
        if let note {
            Text(note)
                .font(WatchFont.secondary)
                .foregroundStyle(WatchColor.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
    }

    private var note: String? {
        switch shape {
        case .warmup: return "No RPE, no PR check, 60 s rest"
        case .amrap:
            let target = store.amrapTargets[set.id] ?? set.reps
            let over = set.reps - target
            let e1rm = SetFormat.e1RM(set.weightKg, reps: set.reps)
                .map { " · e1RM \(unit.format(kg: $0)) \(unit.symbol)" } ?? ""
            return over > 0 ? "\(over) over target\(e1rm)" : "At target\(e1rm)"
        case .assisted: return "Less assistance is progress"
        case .perSide:
            // The capsule already says "Log left" / "Log right"; the 40 mm has no row to spare.
            guard !WatchMetric.isSmall else { return nil }
            return store.hasLoggedLeft(exerciseID: entry.id)
                ? "Left logged · now right" : "Logs left, then asks for right"
        case .standard, .bodyweight, .timedHold, .cardio: return nil
        }
    }
}

/// The L/R pill: which side is live.
struct SidePill: View {
    var isLeft: Bool

    var body: some View {
        HStack(spacing: 0) {
            side("L", live: isLeft)
            side("R", live: !isLeft)
        }
        .background(Capsule().fill(WatchColor.card))
        .frame(width: 84, height: WatchMetric.isSmall ? 20 : 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLeft ? "Left side" : "Right side")
    }

    private func side(_ letter: String, live: Bool) -> some View {
        Text(letter)
            .font(WatchFont.bodyMedium)
            .foregroundStyle(live ? Color.black : WatchColor.inkSecondary)
            .frame(width: 42, height: WatchMetric.isSmall ? 20 : 24)
            .background(Capsule().fill(live ? WatchColor.accent : .clear))
    }
}

/// The 41 mm RPE tap-through: a wheel of the six RPE steps.
struct EffortPickerSheet: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var entry: WorkoutExerciseEntry
    @State private var rpe: Double = 8

    var body: some View {
        VStack {
            Picker("RPE", selection: $rpe) {
                ForEach(Effort.steps, id: \.rpe) { Text($0.displayValue(scale: .rpe)).tag($0.rpe) }
            }
            .labelsHidden()
            CapsuleButton(title: "Set RPE \(Effort(rpe: rpe).displayValue(scale: .rpe))") {
                store.updateSet(exerciseID: entry.id) { $0.effort = Effort(rpe: rpe) }
                dismiss()
            }
        }
        .padding(.horizontal, WatchMetric.gutter)
    }
}
