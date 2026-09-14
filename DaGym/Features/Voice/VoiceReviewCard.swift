import SwiftUI

// PLACEHOLDER STYLING — the owner is designing this card himself. This view exists to make voice
// logging usable end to end (editable fields, on-system tokens, nothing that looks broken), not
// to be the final look. Keep the structure (three labeled fields + two actions) easy to re-skin
// rather than investing in bespoke layout here.

/// The "what I understood" card: shown whenever a voice command didn't clear the auto-log bar
/// (low confidence, a suspicious jump, more than one set, an exercise that needed disambiguation
/// pointed at the on-deck one anyway). Every field is editable before logging.
struct VoiceReviewCard: View {
    @Binding var card: VoiceLogController.ReviewCard
    var onLog: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Heard").dgLabel()
                Text("\u{201C}\(card.transcript)\u{201D}")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(card.exerciseName)
                .font(DGFont.title2)
                .foregroundStyle(DGColor.ink1)

            HStack(spacing: DGSpace.s3) {
                field(label: "Weight (kg)") {
                    TextField(
                        "Weight",
                        value: Binding(get: { card.weightKg ?? 0 }, set: { card.weightKg = $0 }),
                        format: .number
                    )
                }
                field(label: "Reps") {
                    TextField(
                        "Reps",
                        value: Binding(get: { card.reps ?? 0 }, set: { card.reps = $0 }),
                        format: .number
                    )
                }
            }

            HStack(spacing: DGSpace.s3) {
                Button("Discard", role: .cancel, action: onDismiss)
                    .buttonStyle(.plain)
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink2)
                    .padding(.horizontal, DGSpace.s4)
                    .frame(height: 44)
                    .background(DGColor.surface3, in: Capsule())

                DGPrimaryButton(title: "Log set", height: 44, action: onLog)
            }
        }
        .padding(DGSpace.s5)
        .background(DGColor.surface1, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
                .strokeBorder(DGColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func field(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            Text(label).dgLabel()
            content()
                .keyboardType(.decimalPad)
                .font(DGFont.metricM)
                .foregroundStyle(DGColor.ink1)
                .padding(.horizontal, DGSpace.s3)
                .frame(height: 44)
                .background(
                    DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity)
    }
}
