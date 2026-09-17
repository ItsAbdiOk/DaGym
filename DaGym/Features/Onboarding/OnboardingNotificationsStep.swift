import SwiftUI

/// Step 7, "Turn on notifications?" — Allow calls `NotificationPermission.requestIfNeeded()`;
/// the top-bar Skip asks nothing (the rest timer will still ask the first time it actually
/// starts).
struct OnboardingNotificationsStep: View {
    var onNext: () -> Void

    var body: some View {
        OnboardingPage(
            step: .notifications, name: "notifications", symbol: "bell.fill",
            title: "Turn on notifications?",
            message: "Optional. Reminders can be turned on later in Settings.",
            cta: "Allow", onContinue: enable
        ) {
            OnboardingOptionGroup {
                OnboardingInfoRow(
                    symbol: "timer", title: "Rest timer", sub: "A ping when your rest is up — never nagging."
                )
                OnboardingInfoRow(
                    symbol: "calendar", title: "Weekly recap",
                    sub: "Off until you turn reminders on in Settings."
                )
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
        DGColor.bgBase.ignoresSafeArea()
        OnboardingNotificationsStep(onNext: {})
    }
}
