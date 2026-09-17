import SwiftUI

/// First-launch onboarding (plan §6.9): a fixed sequence of full-screen steps on the plain
/// stone page — Back and Skip in the top bar, an accent glyph, kicker, title and a white group
/// of options, then page dots and one full-width call to action. Shown before `RootView`
/// while `preferences.hasCompletedOnboarding` is `false` (see `DaGymApp.swift`).
/// Every step persists its answer immediately — `Preferences` and `WorkoutStore` writes
/// happen as the user taps, not batched at the end — and the current step is saved too, so a
/// killed app resumes where it was rather than losing progress. UI-test launches always start
/// at Welcome.
struct OnboardingFlow: View {
    var onComplete: () -> Void

    @State private var step = OnboardingStep.welcome
    /// True while "Explore with sample data" is building eight weeks of history.
    @State private var isSeeding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    static let savedStepKey = "onboardingStep"

    var body: some View {
        ZStack {
            DGColor.bgBase.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                stepContent
            }
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

    /// Welcome's "Explore with sample data" — seeds the Push/Pull/Legs trio and eight weeks of
    /// history on it, then skips straight to the tab bar, same as "Skip setup". The seed is a
    /// few hundred SwiftData writes on the main actor; the yield lets the busy state paint
    /// first so the tap doesn't look ignored.
    private func exploreSampleData() {
        guard !isSeeding else { return }
        isSeeding = true
        Task {
            await Task.yield()
            SampleDataSeeder.seed(store: store, preferences: preferences)
            isSeeding = false
            complete()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep(
                isSeeding: isSeeding, onStart: advance, onSkip: complete,
                onExploreSampleData: exploreSampleData
            )
        case .units:
            OnboardingUnitsStep(onNext: advance)
        case .goal:
            OnboardingGoalStep(onNext: advance)
        case .schedule:
            OnboardingScheduleStep(onNext: advance)
        case .equipment:
            OnboardingEquipmentStep(onNext: advance)
        case .bodyweight:
            OnboardingBodyweightStep(onNext: advance)
        case .health:
            OnboardingHealthStep(onNext: advance)
        case .notifications:
            OnboardingNotificationsStep(onNext: advance)
        case .done:
            OnboardingDoneStep(onFinish: complete)
        }
    }

    /// "‹ Back" on every step after Welcome; "Skip" everywhere but the final screen. Skip on
    /// Welcome ends onboarding with defaults (`onboardingSkipAll`); on a question it accepts the
    /// current answer and moves on; on an optional step it skips that step (`onboardingSkip`).
    private var topBar: some View {
        HStack {
            if step != .welcome {
                Button(action: back) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Back").font(DGFont.body)
                    }
                    .foregroundStyle(DGColor.coralText)
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel("Back")
            }
            Spacer()
            if step != .done {
                Button("Skip") { step == .welcome ? complete() : advance() }
                    .buttonStyle(.dgControl)
                    .font(DGFont.body)
                    .foregroundStyle(DGColor.coralText)
                    .accessibilityIdentifier(skipIdentifier)
                    .disabled(isSeeding)
            }
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(height: 44)
    }

    private var skipIdentifier: String {
        step == .welcome ? A11yID.onboardingSkipAll : A11yID.onboardingSkip
    }

    /// "Step 2 of 7" for the dots and the kicker.
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
/// (no question, no progress count); `progressSteps` is what the "Step N of 7" kicker counts.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome, units, goal, schedule, equipment, bodyweight, health, notifications, done

    static let progressSteps: [OnboardingStep] = [
        .units, .goal, .schedule, .equipment, .bodyweight, .health, .notifications
    ]

    /// The small bold line above the title.
    var kicker: String {
        switch self {
        case .welcome: "Welcome to DaGym"
        case .done: "All set"
        default: OnboardingFlow.progressLabel(step: self)
        }
    }
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
