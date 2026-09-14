import SwiftUI

// PLACEHOLDER STYLING — the owner is designing this card himself. This view exists to make voice
// logging usable end to end (editable fields, on-system tokens, nothing that looks broken), not
// to be the final look. Keep the structure (three labeled fields + two actions) easy to re-skin
// rather than investing in bespoke layout here.

/// The "what I understood" card: shown whenever a voice command didn't clear the auto-log bar —
/// which, with auto-log off by default, is every command. Every field is editable before logging,
/// and what's typed here goes through `LogCommandValidator` on confirm just like a spoken value.
///
/// Values are shown and edited in the user's own unit. Storage stays canonical kg (plan.md §3);
/// `card.unit` is what this view converts through, so an lb lifter editing "102.5" is editing
/// pounds, not silently writing 102.5 kg.
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

            VStack(alignment: .leading, spacing: 2) {
                Text(card.exerciseName)
                    .font(DGFont.title2)
                    .foregroundStyle(DGColor.ink1)
                if card.setCount > 1 {
                    // "Three sets of eight at sixty" used to write exactly one set and say
                    // nothing about the other two.
                    Text("\(card.setCount) sets — these values apply to each")
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                }
            }

            HStack(spacing: DGSpace.s3) {
                field(label: "Weight (\(card.unit.symbol))") {
                    TextField("Weight", value: weightBinding, format: .number)
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

                DGPrimaryButton(title: card.setCount > 1 ? "Log sets" : "Log set", height: 44, action: onLog)
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

    /// Canonical kg in, the user's unit out — and back. The getter snaps to the unit's own
    /// display step so the field shows "225", not "224.99999".
    private var weightBinding: Binding<Double> {
        Binding(
            get: {
                guard let weightKg = card.weightKg else { return 0 }
                let step = card.unit.displayStep
                return (card.unit.display(kg: weightKg) / step).rounded() * step
            },
            set: { card.weightKg = card.unit.toKg($0) }
        )
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
