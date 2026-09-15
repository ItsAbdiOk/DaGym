import SwiftUI

/// Shown once, the first time an OpenRouter key is saved: says plainly what leaves the phone
/// and when, and asks. Agree sets `coachChatConsentGiven`; Cancel keeps the key but the coach
/// stays off until the lifter reviews this again from Settings.
struct CoachChatConsentSheet: View {
    var onAgree: () -> Void
    var onCancel: () -> Void

    static let statement =
        "Your training data — workouts, body measurements, routines — is sent to OpenRouter and the "
        + "model you pick. Nothing is sent until you ask the coach a question."

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            Image(systemName: "paperplane")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DGColor.aiVioletText)
                .frame(width: 56, height: 56)
                .background(
                    DGColor.surface3, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                Text("Before You Chat")
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Text(Self.statement)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "OpenRouter and the model provider handle that data under their own terms. Chats "
                        + "stay on this phone. You can revoke this any time in Settings → Coach."
                )
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DGPrimaryButton(title: "Agree", action: onAgree)
                .accessibilityIdentifier(A11yID.coachConsentAgree)
            Button("Cancel", action: onCancel)
                .buttonStyle(.dgControl)
                .dgLabel(DGColor.ink3)
                .accessibilityIdentifier(A11yID.coachConsentCancel)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }
}

#Preview {
    CoachChatConsentSheet(onAgree: {}, onCancel: {})
}
