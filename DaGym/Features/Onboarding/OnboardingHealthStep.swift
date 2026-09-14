import SwiftUI

/// "Connect Apple Health?" — mockup 06_01's permissions half. Connecting
/// turns on both Health toggles and calls `HealthSyncService.authorize()`;
/// skipping leaves Health untouched (both stay off, changeable later in
/// Settings).
struct OnboardingHealthStep: View {
    var onNext: () -> Void
    var onSkip: () -> Void
    @Environment(HealthSyncService.self) private var healthSync
    @Environment(Preferences.self) private var preferences
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s6) {
            Text("Connect\nApple Health?")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Label("Bodyweight in, workouts out", systemImage: "heart.fill")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dgCard()
            Text("Skippable — turn it on later in Settings.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
            Spacer()
            VStack(spacing: DGSpace.s3) {
                DGPrimaryButton(title: isConnecting ? "Connecting…" : "Connect", action: connect)
                    .accessibilityIdentifier(A11yID.onboardingNext)
                    .disabled(isConnecting)
                Button("Skip", action: onSkip)
                    .buttonStyle(.dgControl)
                    .font(DGFont.condensedLabel(13))
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink3)
                    .accessibilityIdentifier(A11yID.onboardingSkip)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                AmbientWash()
                OnboardingHealthStep(onNext: {}, onSkip: {})
                    .environment(preferences)
                    .environment(HealthSyncService(
                        healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                    ))
                    .padding(DGSpace.s5)
            }
        )
    }
    return AnyView(EmptyView())
}
