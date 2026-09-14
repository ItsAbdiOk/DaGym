import SwiftUI

/// "What's your main goal?" — stores `preferences.trainingGoal` and, crucially, *applies* it:
/// `applyTrainingGoalDefaults()` writes the rest length and weekly session count each option's
/// subtitle promises, so the answer changes the app instead of being filed away. "General
/// fitness" is pre-selected so Continue is always available without forcing a choice.
struct OnboardingGoalStep: View {
    var onNext: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            Text("What's your\nmain goal?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            VStack(spacing: DGSpace.s3) {
                ForEach(Preferences.TrainingGoal.allCases, id: \.self) { goal in
                    GoalRow(goal: goal, isSelected: preferences.trainingGoal == goal) {
                        preferences.trainingGoal = goal
                        preferences.applyTrainingGoalDefaults()
                        Haptics.step()
                    }
                }
            }
            Spacer()
            DGPrimaryButton(title: "Continue", action: onNext)
                .accessibilityIdentifier(A11yID.onboardingNext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GoalRow: View {
    var goal: Preferences.TrainingGoal
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title.uppercased())
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                    Text(goal.detail)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? DGColor.coral : DGColor.ink4)
            }
            .dgCard(fill: isSelected ? DGColor.coralWash : DGColor.surface1, padding: DGSpace.s4)
        }
        .buttonStyle(.dgCard)
    }
}

#Preview {
    ZStack {
        AmbientWash()
        OnboardingGoalStep(onNext: {})
            .environment(Preferences())
            .padding(DGSpace.s5)
    }
}
