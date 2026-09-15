import SwiftUI

/// The onboarding welcome screen (mockup 06_00 "15a"): brand mark, three
/// value lines, and the choice to walk through setup or skip straight to
/// the app with sensible defaults.
struct OnboardingWelcomeStep: View {
    /// Sample data is being built: every button disables and the sample-data row shows it.
    var isSeeding = false
    var onStart: () -> Void
    var onSkip: () -> Void
    var onExploreSampleData: () -> Void

    private let valueLines = [
        "Unlimited routines and history",
        "Every chart, every export",
        "Coaching that runs on your phone"
    ]

    var body: some View {
        VStack(spacing: DGSpace.s8) {
            Spacer(minLength: DGSpace.s10)
            Image(systemName: "square.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(DGColor.inkOnCoral)
                .frame(width: 96, height: 96)
                .background(
                    DGColor.coral, in: RoundedRectangle(cornerRadius: DGRadius.xl, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(spacing: DGSpace.s3) {
                Text("DaGym")
                    .font(DGFont.title1)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                    .accessibilityIdentifier(A11yID.onboardingStep("welcome"))
                Text("The whole app. No account, no ads, no subscription, nothing held back.")
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.ink3)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                ForEach(valueLines, id: \.self) { line in
                    HStack(spacing: DGSpace.s3) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DGColor.success)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(DGFont.subhead)
                            .foregroundStyle(DGColor.ink2)
                    }
                }
            }
            Spacer()
            VStack(spacing: DGSpace.s3) {
                DGPrimaryButton(title: "Set Up · 5 Questions", action: onStart)
                    .accessibilityIdentifier(A11yID.onboardingNext)
                Button("Skip and start lifting", action: onSkip)
                    .buttonStyle(.dgControl)
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink3)
                    .accessibilityIdentifier(A11yID.onboardingSkipAll)
                Button(action: onExploreSampleData) {
                    HStack(spacing: DGSpace.s2) {
                        if isSeeding {
                            ProgressView().controlSize(.small).tint(DGColor.ink4)
                        }
                        Text(Self.sampleDataTitle(isSeeding: isSeeding))
                    }
                }
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(13))
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink4)
            }
            .disabled(isSeeding)
        }
        .frame(maxWidth: .infinity)
    }

    /// The sample-data row's label; pinned in `SampleDataSeederTests` alongside the seed itself.
    static func sampleDataTitle(isSeeding: Bool) -> String {
        isSeeding ? "Building sample data…" : "Explore with sample data"
    }
}

#Preview {
    ZStack {
        AmbientWash()
        OnboardingWelcomeStep(onStart: {}, onSkip: {}, onExploreSampleData: {})
            .padding(DGSpace.s5)
    }
}
