import SwiftUI

/// "What's your main goal?" — stores `preferences.trainingGoal` ("strength",
/// "muscle" or "general"), defaulting to "general" so Continue is always
/// available without forcing a choice.
struct OnboardingGoalStep: View {
    var onNext: () -> Void
    @Environment(Preferences.self) private var preferences

    private let options: [GoalOption] = [
        GoalOption(key: "strength", title: "Strength", detail: "Heavier lifts, lower reps, longer rest."),
        GoalOption(key: "muscle", title: "Muscle", detail: "More volume, moderate reps, shorter rest."),
        GoalOption(key: "general", title: "General fitness", detail: "A balanced mix, no specific peak.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            Text("What's your\nmain goal?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            VStack(spacing: DGSpace.s3) {
                ForEach(options) { option in
                    GoalRow(option: option, isSelected: preferences.trainingGoal == option.key) {
                        preferences.trainingGoal = option.key
                        Haptics.step()
                    }
                }
            }
            Spacer()
            DGPrimaryButton(title: "Continue", action: onNext)
                .accessibilityIdentifier(A11yID.onboardingNext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if preferences.trainingGoal.isEmpty { preferences.trainingGoal = "general" }
        }
    }
}

private struct GoalOption: Identifiable {
    var key: String
    var title: String
    var detail: String
    var id: String { key }
}

private struct GoalRow: View {
    var option: GoalOption
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title.uppercased())
                        .font(DGFont.title3)
                        .foregroundStyle(DGColor.ink1)
                    Text(option.detail)
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
