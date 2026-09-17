import SwiftUI

/// The final onboarding screen: the answers just given, read back from `Preferences` and the
/// store (so a skipped question shows its default, not a blank), the training-advice
/// disclaimer once, plainly, and the hand-off to `RootView`.
struct OnboardingDoneStep: View {
    var onFinish: () -> Void
    @Environment(Preferences.self) private var preferences
    @Environment(WorkoutStore.self) private var store

    var body: some View {
        OnboardingPage(
            step: .done, name: "done", symbol: "checkmark", title: "You are set up",
            message: "Start whenever you are ready. Suggestions, not medical advice.",
            cta: "Start training", onContinue: onFinish
        ) {
            OnboardingOptionGroup {
                OnboardingSummaryRow(label: "Units", value: unitsLabel)
                OnboardingSummaryRow(label: "Goal", value: preferences.trainingGoal.title)
                OnboardingSummaryRow(label: "Weekly target", value: "\(preferences.weeklyGoal) sessions")
                OnboardingSummaryRow(label: "Equipment", value: activeProfileName)
            }
        }
    }

    private var unitsLabel: String {
        "\(preferences.unitSymbol) · \(preferences.distanceUnit.symbol)"
    }

    private var activeProfileName: String {
        store.equipmentProfiles().first(where: \.isActive)?.name ?? "—"
    }
}

#Preview {
    if let store = PreviewStore.make() {
        ZStack {
            DGColor.bgBase.ignoresSafeArea()
            OnboardingDoneStep(onFinish: {})
                .environment(Preferences())
                .environment(store)
        }
    }
}
