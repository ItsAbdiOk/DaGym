import SwiftUI

/// Step 3, "How many sessions a week?" — sets `preferences.weeklyGoal` (1–7 sessions) with a
/// stepper row, and `preferences.weekStartsMonday` with two option rows, both persisted
/// immediately.
struct OnboardingScheduleStep: View {
    var onNext: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        OnboardingPage(
            step: .schedule, name: "schedule", symbol: "calendar", title: "How many sessions a week?",
            message: "Your streak and weekly goal use this.", cta: "Continue", onContinue: onNext
        ) {
            OnboardingOptionGroup {
                sessionsRow
            }
            OnboardingOptionGroup {
                OnboardingOptionRow(
                    title: "Monday", sub: "Week starts", isSelected: preferences.weekStartsMonday
                ) { setWeekStart(monday: true) }
                OnboardingOptionRow(
                    title: "Sunday", sub: "Week starts", isSelected: !preferences.weekStartsMonday
                ) { setWeekStart(monday: false) }
            }
            .padding(.top, DGSpace.s3)
        }
    }

    private var sessionsRow: some View {
        HStack(spacing: DGSpace.s3) {
            Text("Sessions a week").font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            stepperButton(symbol: "minus") { adjustGoal(by: -1) }
            Text("\(preferences.weeklyGoal)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DGColor.ink1)
                .monospacedDigit()
                .frame(minWidth: 28)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(preferences.weeklyGoal) sessions a week")
            stepperButton(symbol: "plus", coral: true) { adjustGoal(by: 1) }
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: 56)
    }

    private func stepperButton(
        symbol: String, coral: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(coral ? DGColor.inkOnCoral : DGColor.ink1)
                .frame(width: 36, height: 36)
                .background(coral ? DGColor.coral : DGColor.surface3, in: Circle())
        }
        .buttonStyle(.dgControl)
        .accessibilityLabel(symbol == "minus" ? "Fewer sessions" : "More sessions")
    }

    private func adjustGoal(by delta: Int) {
        preferences.weeklyGoal = min(7, max(1, preferences.weeklyGoal + delta))
        Haptics.step()
    }

    private func setWeekStart(monday: Bool) {
        preferences.weekStartsMonday = monday
        Haptics.step()
    }
}

#Preview {
    ZStack {
        DGColor.bgBase.ignoresSafeArea()
        OnboardingScheduleStep(onNext: {})
            .environment(Preferences())
    }
}
