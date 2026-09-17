import SwiftUI

/// The final onboarding screen: confirms setup is done and states the
/// training-advice disclaimer once, plainly, before handing off to
/// `RootView`.
struct OnboardingDoneStep: View {
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: DGSpace.s8) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(DGColor.success)
                .accessibilityHidden(true)
            VStack(spacing: DGSpace.s3) {
                Text("You're Set")
                    .font(DGFont.title1)
                    .foregroundStyle(DGColor.ink1)
                    .accessibilityIdentifier(A11yID.onboardingStep("done"))
                Text("Suggestions, not medical advice.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            DGPrimaryButton(title: "Get Started", action: onFinish)
                .accessibilityIdentifier(A11yID.onboardingNext)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ZStack {
        AmbientWash()
        OnboardingDoneStep(onFinish: {})
            .padding(DGSpace.s5)
    }
}
