import SwiftUI

/// Step 2, "What are you training for?" — stores `preferences.trainingGoal` and, crucially,
/// *applies* it: `applyTrainingGoalDefaults()` writes the rest length and weekly session count
/// each option's subtitle promises, so the answer changes the app instead of being filed away.
/// "General fitness" is pre-selected so Continue is always available without forcing a choice.
struct OnboardingGoalStep: View {
    var onNext: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        OnboardingPage(
            step: .goal, name: "goal", symbol: "target", title: "What are you training for?",
            message: "This sets your default rest and weekly target.", cta: "Continue", onContinue: onNext
        ) {
            OnboardingOptionGroup {
                ForEach(Preferences.TrainingGoal.allCases, id: \.self) { goal in
                    OnboardingOptionRow(
                        title: goal.title, sub: goal.detail, isSelected: preferences.trainingGoal == goal
                    ) {
                        preferences.trainingGoal = goal
                        preferences.applyTrainingGoalDefaults()
                        Haptics.step()
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        DGColor.bgBase.ignoresSafeArea()
        OnboardingGoalStep(onNext: {})
            .environment(Preferences())
    }
}
