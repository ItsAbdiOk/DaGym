import SwiftUI

/// "Turn on notifications?" — mockup 06_01's permissions half. Allowing
/// calls `NotificationPermission.requestIfNeeded()`; skipping asks nothing
/// (the rest timer will still ask the first time it actually starts).
struct OnboardingNotificationsStep: View {
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            Text("Turn on\nnotifications?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Label("Rest timer only, never nagging", systemImage: "bell.fill")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink2)
                .dgCard()
            Text("Skippable — turn it on later in Settings.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
            Spacer()
            VStack(spacing: DGSpace.s3) {
                DGPrimaryButton(title: "Allow", action: enable)
                    .accessibilityIdentifier(A11yID.onboardingNext)
                Button("Skip", action: onSkip)
                    .buttonStyle(.plain)
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink3)
                    .accessibilityIdentifier(A11yID.onboardingSkip)
            }
        }
    }

    private func enable() {
        NotificationPermission.requestIfNeeded()
        onNext()
    }
}

#Preview {
    ZStack {
        AmbientWash()
        OnboardingNotificationsStep(onNext: {}, onSkip: {})
            .padding(DGSpace.s5)
    }
}
