import GymCore
import SwiftUI

/// The "How To Do It" card on `ExerciseDetailView`.
///
/// Seeded instructions arrive as one string with the numbering inline, so
/// `ExerciseInstructions.steps(from:)` recovers the steps and this renders them as a real
/// numbered list: the number in its own column, the step text in the next, so a wrapped line
/// indents under the text rather than under the number.
///
/// Instructions that were never numbered (most wger-sourced ones) come back as a single
/// unnumbered step and render as the plain paragraph they have always been — no invented numbers.
struct ExerciseInstructionsCard: View {
    var steps: [ExerciseInstructionStep]
    var emptyText: String = "Instructions coming soon"

    /// Width of the number column. `@ScaledMetric` so it grows with Dynamic Type; `minWidth`
    /// rather than a fixed width so a two-digit step at the largest accessibility sizes pushes
    /// the column wider instead of clipping or truncating.
    @ScaledMetric(relativeTo: .body) private var numberColumnWidth: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("How To Do It").dgLabel()
            if steps.isEmpty {
                Text(emptyText)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            } else {
                ForEach(steps) { step in
                    row(step)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dgCard()
    }

    @ViewBuilder
    private func row(_ step: ExerciseInstructionStep) -> some View {
        if let number = step.number {
            // `.firstTextBaseline` keeps the number sitting on the same baseline as the first
            // line of its step at every Dynamic Type size.
            HStack(alignment: .firstTextBaseline, spacing: DGSpace.s2) {
                Text("\(number).")
                    .font(DGFont.body)
                    .monospacedDigit()
                    .foregroundStyle(DGColor.ink3)
                    .frame(minWidth: numberColumnWidth, alignment: .trailing)
                    .accessibilityHidden(true)
                Text(step.text)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // One VoiceOver element per step, read as "Step 3, …" rather than "3 period".
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(number). \(step.text)")
        } else {
            Text(step.text)
                .font(DGFont.body)
                .foregroundStyle(DGColor.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: DGSpace.s4) {
            ExerciseInstructionsCard(steps: ExerciseInstructions.steps(from: """
                1. Hold a kettlebell by the handle at waist height, hinging slightly at the hips. \
                2. Explosively extend your hips and knees, pulling the kettlebell upward and into \
                the rack position at your shoulder. 3. Lower back down and repeat on the opposite \
                arm. The power comes from your hips and hamstrings, not your arms.
                """))
            ExerciseInstructionsCard(steps: ExerciseInstructions.steps(from: """
                Lay down on a bench, the bar should be directly above your eyes, the knees are \
                somewhat angled and the feet are firmly on the floor.
                """))
            ExerciseInstructionsCard(steps: ExerciseInstructions.steps(from: ""))
        }
        .padding(DGSpace.s4)
    }
    .background(DGColor.bgBase)
}
