import GymCore
import SwiftUI

/// "Finish this workout?" — the small-detent sheet behind the header's Finish pill: what
/// finishing now would save, then accent "Finish", red "Discard workout" and "Keep going".
struct FinishWorkoutSheet: View {
    /// "4 / 19 sets done · 25:05 elapsed", or "Nothing logged yet".
    var prompt: String
    var onFinish: () -> Void
    var onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                Text("Finish this workout?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.ink1)
                Text(prompt)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink2)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, DGSpace.s5)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Divider().overlay(DGColor.hairline)
            row("Finish", tint: DGColor.coralText, weight: .semibold) {
                dismiss()
                onFinish()
            }
            // The UI smoke test (and VoiceOver) asks for the fuller name.
            .accessibilityLabel("Finish workout")
            Divider().overlay(DGColor.hairline)
            row("Discard workout", tint: DGColor.danger) {
                dismiss()
                onDiscard()
            }
            Divider().overlay(DGColor.hairline)
            row("Keep going", tint: DGColor.ink1) { dismiss() }
        }
        .padding(.horizontal, DGSpace.s2)
        .padding(.bottom, DGSpace.s2)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(DGColor.bgBase)
        .presentationCornerRadius(DGRadius.lg)
    }

    private func row(
        _ title: String, tint: Color, weight: Font.Weight = .regular, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: weight))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
    }
}

/// The per-exercise "…" sheet: every set-level and structural action for one entry, as a
/// white row group under the exercise's name. Rows that make no sense for the entry (warm-ups
/// on a run, "Superset with previous" on the first exercise) are simply absent, as they were in
/// the old confirmation dialog.
struct ExerciseActionsSheet: View {
    struct Options {
        var name: String
        var isCardio: Bool
        var hasPrevious: Bool
        var hasNext: Bool
        var isInSuperset: Bool
    }

    enum Action {
        case addSet(SetKind)
        case generateWarmups
        case pairPrevious, pairNext, unpair
        case notes, swap, remove
    }

    var options: Options
    var onAction: (Action) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WorkoutChoiceSheet(title: options.name) {
            ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                WorkoutChoiceRow(
                    title: row.title, tint: row.tint, isLast: offset == rows.count - 1
                ) {
                    dismiss()
                    onAction(row.action)
                }
            }
        }
        .presentationDetents([.height(CGFloat(rows.count) * 48 + 132)])
    }

    private struct Row {
        var title: String
        var action: Action
        var tint: Color = DGColor.ink1
    }

    private var rows: [Row] {
        var rows = [
            Row(title: "Add set", action: .addSet(.working)),
            Row(title: "Add warm-up set", action: .addSet(.warmup))
        ]
        // A run has no load to ramp up to.
        if !options.isCardio { rows.append(Row(title: "Generate warm-ups", action: .generateWarmups)) }
        rows.append(Row(title: "Add drop set", action: .addSet(.drop)))
        rows.append(Row(title: "Add rest-pause set", action: .addSet(.restPause)))
        if options.hasPrevious { rows.append(Row(title: "Superset with previous", action: .pairPrevious)) }
        if options.hasNext { rows.append(Row(title: "Superset with next", action: .pairNext)) }
        if options.isInSuperset { rows.append(Row(title: "Unpair superset", action: .unpair)) }
        rows.append(Row(title: "Exercise notes", action: .notes))
        rows.append(Row(title: "Swap exercise", action: .swap))
        rows.append(Row(title: "Remove exercise", action: .remove, tint: DGColor.danger))
        return rows
    }
}

#Preview("Finish") {
    Color.clear.sheet(isPresented: .constant(true)) {
        FinishWorkoutSheet(prompt: "4 / 19 sets done · 25:05 elapsed", onFinish: {}, onDiscard: {})
    }
}

#Preview("Exercise actions") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ExerciseActionsSheet(
            options: .init(
                name: "Barbell Bench Press", isCardio: false, hasPrevious: false, hasNext: true,
                isInSuperset: false
            ),
            onAction: { _ in }
        )
    }
}
