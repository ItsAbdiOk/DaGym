import SwiftUI

/// "How often do you train?" — sets `preferences.weeklyGoal` (1–7 sessions)
/// and `preferences.weekStartsMonday`, both persisted immediately.
struct OnboardingScheduleStep: View {
    var onNext: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            Text("How often do\nyou train?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            weeklyGoalCard
            weekStartCard
            Spacer()
            DGPrimaryButton(title: "Continue", action: onNext)
                .accessibilityIdentifier(A11yID.onboardingNext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklyGoalCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Weekly Goal").dgLabel()
            HStack {
                stepperButton(symbol: "minus") { adjustGoal(by: -1) }
                Spacer()
                VStack(spacing: 0) {
                    Text("\(preferences.weeklyGoal)")
                        .dgMetric(DGFont.metricXL)
                        .foregroundStyle(DGColor.ink1)
                    Text("sessions").dgLabel()
                }
                Spacer()
                stepperButton(symbol: "plus", coral: true) { adjustGoal(by: 1) }
            }
        }
        .dgCard()
    }

    private var weekStartCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Week Starts").dgLabel()
            HStack(spacing: DGSpace.s2) {
                DGChip(title: "Monday", selected: preferences.weekStartsMonday) {
                    preferences.weekStartsMonday = true
                }
                DGChip(title: "Sunday", selected: !preferences.weekStartsMonday) {
                    preferences.weekStartsMonday = false
                }
            }
        }
        .dgCard()
    }

    private func stepperButton(
        symbol: String, coral: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(coral ? DGColor.inkOnCoral : DGColor.ink1)
                .frame(width: 44, height: 44)
                .background(coral ? DGColor.coral : DGColor.surface3, in: Circle())
        }
        .buttonStyle(.dgControl)
    }

    private func adjustGoal(by delta: Int) {
        preferences.weeklyGoal = min(7, max(1, preferences.weeklyGoal + delta))
        Haptics.step()
    }
}

#Preview {
    ZStack {
        AmbientWash()
        OnboardingScheduleStep(onNext: {})
            .environment(Preferences())
            .padding(DGSpace.s5)
    }
}
