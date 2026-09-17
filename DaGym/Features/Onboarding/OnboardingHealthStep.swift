import SwiftUI

/// Step 6, "Connect Apple Health?" — Connect turns on the write toggles HealthKit actually
/// granted and calls `HealthSyncService.authorize()`; the top-bar Skip leaves Health untouched
/// (both stay off, changeable later in Settings).
struct OnboardingHealthStep: View {
    var onNext: () -> Void
    @Environment(HealthSyncService.self) private var healthSync
    @Environment(Preferences.self) private var preferences
    @State private var isConnecting = false

    var body: some View {
        OnboardingPage(
            step: .health, name: "health", symbol: "heart.fill", title: "Connect Apple Health?",
            message: "Optional. Everything here can be turned on later in Settings.",
            cta: isConnecting ? "Connecting…" : "Connect", ctaDisabled: isConnecting, onContinue: connect
        ) {
            OnboardingOptionGroup {
                OnboardingInfoRow(
                    symbol: "arrow.down.circle", title: "Bodyweight in",
                    sub: "Weigh-ins sync both ways, full history included."
                )
                OnboardingInfoRow(
                    symbol: "arrow.up.circle", title: "Workouts out",
                    sub: "Each finished session is saved as a strength workout."
                )
            }
        }
    }

    /// Turns the two write toggles on only for what the user actually granted. HealthKit keeps
    /// read permission opaque, but it will say whether a *write* was authorized or denied — so a
    /// declined sheet no longer leaves "Save workouts to Health" and "Sync bodyweight" switched
    /// on, claiming a sync that silently can't happen.
    private func connect() {
        isConnecting = true
        Task {
            await healthSync.authorize()
            preferences.healthWriteWorkouts = await healthSync.canWrite(.workouts)
            preferences.healthSyncBodyweight = await healthSync.canWrite(.bodyMass)
            isConnecting = false
            onNext()
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        let preferences = Preferences()
        return AnyView(
            ZStack {
                DGColor.bgBase.ignoresSafeArea()
                OnboardingHealthStep(onNext: {})
                    .environment(preferences)
                    .environment(HealthSyncService(
                        healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                    ))
            }
        )
    }
    return AnyView(EmptyView())
}
