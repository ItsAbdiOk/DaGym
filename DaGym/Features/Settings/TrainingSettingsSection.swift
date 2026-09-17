import GymCore
import SwiftUI

/// Settings › Training: goal, weekly goal, week start, weigh-in prompt and the gym card row.
struct TrainingSettingsSection: View {
    @Environment(Preferences.self) private var preferences
    @Environment(WorkoutStore.self) private var store

    /// The weekly-goal stepper needs its own reschedule (S14/F14): `RemindersSettingsSection`'s
    /// three bindings reschedule on change, but the notification body embeds
    /// `weeklyGoal - thisWeekCount` at schedule time, so a goal edit here must reschedule too or
    /// Saturday's push keeps saying the old number. `static`: a stored property was rebuilt on
    /// every `SettingsView` render.
    private static let notificationScheduler = TrainingNotificationScheduler()

    var body: some View {
        SettingsSection(note: goalNote) {
            SettingsRow(label: "Goal") {
                SettingsSegment(
                    label: "Goal", selection: goalBinding,
                    options: Preferences.TrainingGoal.allCases.map { ($0, $0.shortTitle) }
                )
            }
            SettingsDivider()
            SettingsRow(label: "Weekly goal") {
                Stepper(value: weeklyGoalBinding, in: 1...7) {
                    Text("\(preferences.weeklyGoal) sessions")
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                        .monospacedDigit()
                }
                .accessibilityLabel("Weekly goal")
                .accessibilityValue("\(preferences.weeklyGoal) workouts")
            }
            SettingsDivider()
            SettingsRow(label: "Week starts") {
                SettingsSegment(
                    label: "Week starts", selection: weekStartsMondayBinding,
                    options: [(true, "Mon"), (false, "Sun")]
                )
            }
            SettingsDivider()
            SettingsToggleRow(label: "Weigh in before workouts", isOn: binding(\.weighInBeforeWorkout))
        }
        CheckInCardButton()
    }

    /// The goal's own one-liner plus what changing it re-applies — the two numbers the goal
    /// actually drives, so the answer never reads as a stored string nobody uses.
    private var goalNote: String {
        "\(preferences.trainingGoal.detail) Your goal sets default rest and the weekly session target."
    }

    /// Changing the goal re-applies its rest length and weekly session count (what the note
    /// promises) and reschedules the notifications that embed the weekly number.
    private var goalBinding: Binding<Preferences.TrainingGoal> {
        Binding(
            get: { preferences.trainingGoal },
            set: {
                preferences.trainingGoal = $0
                preferences.applyTrainingGoalDefaults()
                Self.notificationScheduler.rescheduleAll(store: store, preferences: preferences)
            }
        )
    }

    /// "This week" moving changes which days the goal-at-risk and recap notifications belong to,
    /// so the pending ones have to be rebuilt — otherwise the change only lands on next launch.
    private var weekStartsMondayBinding: Binding<Bool> {
        Binding(
            get: { preferences.weekStartsMonday },
            set: {
                preferences.weekStartsMonday = $0
                Self.notificationScheduler.rescheduleAll(store: store, preferences: preferences)
                WidgetSnapshotWriter.refresh(store: store, preferences: preferences)
            }
        )
    }

    private var weeklyGoalBinding: Binding<Int> {
        Binding(
            get: { preferences.weeklyGoal },
            set: {
                preferences.weeklyGoal = $0
                Self.notificationScheduler.rescheduleAll(store: store, preferences: preferences)
            }
        )
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }
}

extension Preferences.TrainingGoal {
    /// The segment label: "General fitness" is too long for a three-way pill.
    var shortTitle: String {
        switch self {
        case .strength: "Strength"
        case .muscle: "Muscle"
        case .general: "General"
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            SettingsPage(title: "Training") { TrainingSettingsSection() }
        }
        .environment(Preferences())
        .environment(store)
    }
}
