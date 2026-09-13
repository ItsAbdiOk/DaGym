import GymCore
import SwiftUI

/// Settings "REMINDERS" section: the two training-notification toggles plus the hour they fire
/// at (plan.md §6.4), and the workout-day reminder (OpenGym parity, features "Adopt now" #3).
/// Bound directly to `Preferences`; `TrainingNotificationScheduler.bind(to:)` reschedules
/// automatically after every finished workout, but a toggle here needs an immediate reschedule
/// too, so this section triggers one itself.
struct RemindersSettingsSection: View {
    @Environment(Preferences.self) private var preferences
    @Environment(WorkoutStore.self) private var store

    private let scheduler = TrainingNotificationScheduler()

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Reminders").dgLabel()
            VStack(spacing: 0) {
                ReminderRow(label: "Streak reminders") {
                    Toggle("", isOn: streakBinding).tint(DGColor.coral).labelsHidden()
                }
                ReminderDivider()
                ReminderRow(label: "Weekly recap") {
                    Toggle("", isOn: recapBinding).tint(DGColor.coral).labelsHidden()
                }
                ReminderDivider()
                ReminderRow(label: "Reminder time") {
                    Stepper(value: hourBinding, in: 0...23) {
                        Text(hourLabel).font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                    }
                }
                ReminderDivider()
                ReminderRow(label: "Workout day reminder") {
                    Toggle("", isOn: workoutDayEnabledBinding).tint(DGColor.coral).labelsHidden()
                }
                if preferences.workoutDayReminderEnabled {
                    ReminderDivider()
                    ReminderRow(label: "Workout day time") {
                        Stepper(value: workoutDayHourBinding, in: 0...23) {
                            Text(workoutDayHourLabel).font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                        }
                    }
                }
            }
            .dgCard(padding: 0)
            Text("A Saturday nudge when the weekly goal is at risk, a Sunday recap, and a reminder"
                + " on each day you've scheduled a routine.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var streakBinding: Binding<Bool> {
        Binding(
            get: { preferences.streakRemindersEnabled },
            set: { preferences.streakRemindersEnabled = $0; reschedule() }
        )
    }

    private var recapBinding: Binding<Bool> {
        Binding(
            get: { preferences.weeklyRecapEnabled },
            set: { preferences.weeklyRecapEnabled = $0; reschedule() }
        )
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { preferences.reminderHour },
            set: { preferences.reminderHour = $0; reschedule() }
        )
    }

    private var workoutDayEnabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.workoutDayReminderEnabled },
            set: { preferences.workoutDayReminderEnabled = $0; reschedule() }
        )
    }

    private var workoutDayHourBinding: Binding<Int> {
        Binding(
            get: { preferences.workoutDayReminderHour },
            set: { preferences.workoutDayReminderHour = $0; reschedule() }
        )
    }

    private func reschedule() {
        scheduler.rescheduleAll(store: store, preferences: preferences)
    }

    private var hourLabel: String { Self.hourLabel(preferences.reminderHour) }
    private var workoutDayHourLabel: String { Self.hourLabel(preferences.workoutDayReminderHour) }

    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }
}

/// One "label … trailing control" row, matching `SettingsView`'s row chrome without reusing its
/// file-private `SettingsRow` (see `DataSettingsSection`'s `DataRow` for the same convention).
private struct ReminderRow<Trailing: View>: View {
    var label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(label).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            trailing
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }
}

private struct ReminderDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        return AnyView(
            ScrollView {
                RemindersSettingsSection()
                    .padding(DGSpace.s4)
            }
            .environment(Preferences())
            .environment(store)
            .background(AmbientWash())
        )
    }
    return AnyView(EmptyView())
}
