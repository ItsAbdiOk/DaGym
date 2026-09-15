import GymCore
import SwiftUI

/// The Settings "TRAINING" card: goal, weekly goal, week start, weigh-in prompt and the gym
/// check-in card row.
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
        SettingsSection(title: "Training") {
            TrainingGoalRow(onApply: {
                preferences.applyTrainingGoalDefaults()
                Self.notificationScheduler.rescheduleAll(store: store, preferences: preferences)
            })
            SettingsDivider()
            SettingsRow(label: "Weekly goal") {
                Stepper(value: weeklyGoalBinding, in: 1...7) {
                    Text("\(preferences.weeklyGoal)").font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                }
                .accessibilityLabel("Weekly goal")
                .accessibilityValue("\(preferences.weeklyGoal) workouts")
            }
            SettingsDivider()
            SettingsRow(label: "Week starts") {
                Picker("Week starts", selection: weekStartsMondayBinding) {
                    Text("MON").tag(true)
                    Text("SUN").tag(false)
                }
                .pickerStyle(.segmented)
                .tint(DGColor.coral)
                .frame(width: 120)
            }
            SettingsDivider()
            SettingsRow(label: "Weigh in before workouts") {
                Toggle("Weigh in before workouts", isOn: binding(\.weighInBeforeWorkout))
                    .tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            CheckInCardButton()
        }
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

#Preview {
    if let store = PreviewStore.make() {
        ScrollView {
            TrainingSettingsSection()
                .padding(DGSpace.s4)
        }
        .environment(Preferences())
        .environment(store)
        .background(AmbientWash())
    }
}
