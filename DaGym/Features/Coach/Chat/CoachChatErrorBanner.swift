import SwiftUI

/// The strip above the input bar when a turn failed: `CoachChatErrorCopy`'s title and line,
/// one action (Settings, openrouter.ai or Retry) when there is a useful one, and a dismiss.
/// Never the server's raw sentence — that's the copy table's job.
struct CoachChatErrorBanner: View {
    var banner: CoachChatErrorCopy.Banner
    var onAction: (CoachChatErrorCopy.Action) -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DGSpace.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DGColor.warning)
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                Text(banner.title)
                    .font(DGFont.title3)
                    .foregroundStyle(DGColor.ink1)
                Text(banner.message)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = banner.action, let title = banner.actionTitle {
                    Button { onAction(action) } label: {
                        Text(title)
                            .font(DGFont.condensedLabel(12))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(DGColor.coralText)
                            .frame(minHeight: DGTap.min)
                    }
                    .buttonStyle(.dgControl)
                    .accessibilityIdentifier(A11yID.coachChatErrorAction)
                }
            }
            Spacer(minLength: DGSpace.s2)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink3)
                    .frame(width: DGTap.min, height: DGTap.min)
            }
            .buttonStyle(.dgControl)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, DGSpace.s4)
        .padding(.vertical, DGSpace.s3)
        .dgCard(radius: DGRadius.md, fill: DGColor.surface2, padding: 0)
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.coachChatErrorBanner)
    }
}

#Preview {
    VStack(spacing: DGSpace.s3) {
        CoachChatErrorBanner(
            banner: CoachChatErrorCopy.banner(for: .unauthorized), onAction: { _ in }, onDismiss: {}
        )
        CoachChatErrorBanner(
            banner: CoachChatErrorCopy.banner(for: .rateLimited(retryAfter: 12)), onAction: { _ in },
            onDismiss: {}
        )
    }
    .background(AmbientWash())
}
