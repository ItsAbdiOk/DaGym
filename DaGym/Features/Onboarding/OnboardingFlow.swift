import SwiftUI

/// First-launch onboarding (plan §6.9): a fixed sequence of short glass-card
/// steps over `AmbientWash`, shown before `RootView` while
/// `preferences.hasCompletedOnboarding` is `false` (see `DaGymApp.swift`).
/// Every step persists its answer immediately — `Preferences` and
/// `WorkoutStore` writes happen as the user taps, not batched at the end —
/// and the current step is saved too, so a killed app resumes where it was
/// rather than losing progress. UI-test launches always start at Welcome.
struct OnboardingFlow: View {
    var onComplete: () -> Void

    @State private var step = OnboardingStep.welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    static let savedStepKey = "onboardingStep"

    var body: some View {
        ZStack {
            AmbientWash()
            VStack(spacing: DGSpace.s6) {
                header
                stepContent
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DGSpace.s5)
            .padding(.top, DGSpace.s8)
            .padding(.bottom, DGSpace.s5)
        }
        .animation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion), value: step)
        .onAppear(perform: restoreStep)
        .onChange(of: step) { UserDefaults.standard.set(step.rawValue, forKey: Self.savedStepKey) }
    }

    private func restoreStep() {
        guard !LaunchFlags.isTesting,
              let saved = OnboardingStep(rawValue: UserDefaults.standard.integer(forKey: Self.savedStepKey)),
              saved != .done else { return }
        step = saved
    }

    private func complete() {
        UserDefaults.standard.removeObject(forKey: Self.savedStepKey)
        onComplete()
    }

    /// Welcome's "Explore with sample data" — seeds eight weeks of history on the starter
    /// routines and skips straight to the tab bar, same as "Skip and start lifting".
    private func exploreSampleData() {
        SampleDataSeeder.seed(store: store, preferences: preferences)
        complete()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep(onStart: advance, onSkip: complete, onExploreSampleData: exploreSampleData)
        case .units:
            OnboardingUnitsStep(onNext: advance)
        case .goal:
            OnboardingGoalStep(onNext: advance)
        case .schedule:
            OnboardingScheduleStep(onNext: advance)
        case .equipment:
            OnboardingEquipmentStep(onNext: advance)
        case .bodyweight:
            OnboardingBodyweightStep(onNext: advance, onSkip: advance)
        case .health:
            OnboardingHealthStep(onNext: advance, onSkip: advance)
        case .notifications:
            OnboardingNotificationsStep(onNext: advance, onSkip: advance)
        case .done:
            OnboardingDoneStep(onFinish: complete)
        }
    }

    @ViewBuilder
    private var header: some View {
        if step != .welcome {
            HStack(spacing: DGSpace.s4) {
                Button(action: back) {
                    Image(systemName: "chevron.left").accessibilityHidden(true)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DGColor.ink2)
                        .frame(width: 36, height: 36)
                        .dgGlass(.thin, in: Circle())
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel("Back")
                progressDots
                Color.clear.frame(width: 36, height: 36)
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: DGSpace.s2) {
            ForEach(OnboardingStep.progressSteps, id: \.self) { candidate in
                Capsule()
                    .fill(candidate.rawValue <= step.rawValue ? DGColor.coral : DGColor.surface3)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.progressLabel(step: step))
    }

    /// "Step 2 of 7" for the dots.
    static func progressLabel(step: OnboardingStep) -> String {
        let steps = OnboardingStep.progressSteps
        let index = (steps.firstIndex(of: step) ?? 0) + 1
        return "Step \(index) of \(steps.count)"
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            complete()
            return
        }
        step = next
    }

    private func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}

/// The nine onboarding screens, in order. `welcome` and `done` are bookends
/// (no question, no progress dot); `progressSteps` is the "5 questions" the
/// mockup's progress bar counts (plus the two permission asks).
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome, units, goal, schedule, equipment, bodyweight, health, notifications, done

    static let progressSteps: [OnboardingStep] = [
        .units, .goal, .schedule, .equipment, .bodyweight, .health, .notifications
    ]
}

#Preview {
    if let store = PreviewStore.make() {
        let preferences = Preferences()
        return AnyView(
            OnboardingFlow(onComplete: {})
                .environment(preferences)
                .environment(store)
                .environment(HealthSyncService(
                    healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                ))
        )
    }
    return AnyView(EmptyView())
}
