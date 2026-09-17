import SwiftUI

/// The onboarding welcome screen: three ways in — walk the five questions, explore eight weeks
/// of sample history, or skip straight to the app with defaults. One is picked in the list and
/// Continue acts on it, so the single call to action stays where every other step has it.
struct OnboardingWelcomeStep: View {
    /// Sample data is being built: every button disables and the call to action says so.
    var isSeeding = false
    var onStart: () -> Void
    var onSkip: () -> Void
    var onExploreSampleData: () -> Void

    @State private var mode = Mode.setup

    enum Mode { case setup, sample, skip }

    var body: some View {
        OnboardingPage(
            step: .welcome, name: "welcome", symbol: "dumbbell.fill",
            title: "Five questions and you are training",
            message: "You can change any of this later. Nothing is locked in.",
            cta: isSeeding ? Self.sampleDataTitle(isSeeding: true) : "Continue",
            ctaDisabled: isSeeding, onContinue: proceed
        ) {
            OnboardingOptionGroup {
                OnboardingOptionRow(
                    title: "Set me up", sub: "Units, goal, schedule, equipment", isSelected: mode == .setup
                ) { pick(.setup) }
                OnboardingOptionRow(
                    title: Self.sampleDataTitle(isSeeding: false), sub: "Eight weeks of example history",
                    isSelected: mode == .sample
                ) { pick(.sample) }
                OnboardingOptionRow(
                    title: "Skip setup", sub: "Start with the defaults now", isSelected: mode == .skip
                ) { pick(.skip) }
            }
            .disabled(isSeeding)
        }
    }

    private func pick(_ new: Mode) {
        mode = new
        Haptics.step()
    }

    private func proceed() {
        switch mode {
        case .setup: onStart()
        case .sample: onExploreSampleData()
        case .skip: onSkip()
        }
    }

    /// The sample-data row's label; pinned in `SampleDataSeederTests` alongside the seed itself.
    static func sampleDataTitle(isSeeding: Bool) -> String {
        isSeeding ? "Building sample data…" : "Explore with sample data"
    }
}

#Preview {
    ZStack {
        DGColor.bgBase.ignoresSafeArea()
        OnboardingWelcomeStep(onStart: {}, onSkip: {}, onExploreSampleData: {})
    }
}
