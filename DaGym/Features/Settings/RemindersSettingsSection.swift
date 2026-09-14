import GymCore
import SwiftUI
import UIKit
import UserNotifications

/// Notification permission as Settings needs it: what iOS currently thinks, and an ask that only
/// happens when a lifter actually turns a reminder on.
///
/// This exists because the toggles used to flip a preference and reschedule without ever asking:
/// someone who skipped onboarding's "Allow" turned on "Workout day reminder", watched the toggle
/// stay on, and never received a single notification. A scheduled `UNNotificationRequest` on an
/// unauthorised app is silently dropped.
@Observable
@MainActor
final class ReminderPermissionState {
    private(set) var status: UNAuthorizationStatus = .notDetermined
    private let authorization: any NotificationAuthorizing

    init(authorization: any NotificationAuthorizing = SystemNotificationAuthorization()) {
        self.authorization = authorization
    }

    /// True when iOS will drop everything we schedule and only the user can undo it.
    var isDenied: Bool { status == .denied }

    func refresh() async {
        status = await authorization.status()
    }

    /// Turning a reminder *on* is the moment to ask; turning one off just re-reads, so a
    /// permission revoked in iOS Settings still shows up here.
    func toggled(on isOn: Bool) async {
        status = isOn ? await authorization.request() : await authorization.status()
    }
}

/// Settings "REMINDERS" section: the two training-notification toggles plus the hour they fire
/// at (plan.md §6.4), and the workout-day reminder (OpenGym parity, features "Adopt now" #3).
/// Bound directly to `Preferences`; `TrainingNotificationScheduler.bind(to:)` reschedules
/// automatically after every finished workout, but a toggle here needs an immediate reschedule
/// too, so this section triggers one itself — and now asks for permission first.
struct RemindersSettingsSection: View {
    /// Injectable so `FeatureSettingsTests` can drive the granted/denied/not-determined states.
    var permission = ReminderPermissionState()

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
                if showsDeniedRow {
                    ReminderDivider()
                    deniedRow
                }
            }
            .dgCard(padding: 0)
            Text("A Saturday nudge when the weekly goal is at risk, a Sunday recap, and a reminder"
                + " on each day you've scheduled a routine.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
        .task { await permission.refresh() }
    }

    /// Only worth saying when something is switched on that iOS is going to drop on the floor.
    private var showsDeniedRow: Bool {
        permission.isDenied && anyReminderEnabled
    }

    private var anyReminderEnabled: Bool {
        preferences.streakRemindersEnabled || preferences.weeklyRecapEnabled
            || preferences.workoutDayReminderEnabled
    }

    private var deniedRow: some View {
        Button(action: openSystemSettings) {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are off in iOS Settings")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                        .multilineTextAlignment(.leading)
                    Text("These reminders can't be delivered until you turn them back on.")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink4)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: DGSpace.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .padding(.horizontal, DGSpace.s5)
            .padding(.vertical, DGSpace.s3)
            .frame(minHeight: 52)
        }
        .buttonStyle(.dgRow)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Every reminder toggle follows the same shape: write the preference, ask for permission if
    /// it just went on, then reschedule. Permission first — a reschedule before the prompt
    /// resolves just queues requests iOS is still entitled to drop on the floor.
    private var streakBinding: Binding<Bool> {
        Binding(
            get: { preferences.streakRemindersEnabled },
            set: { isOn in
                preferences.streakRemindersEnabled = isOn
                requestThenReschedule(isOn)
            }
        )
    }

    private var recapBinding: Binding<Bool> {
        Binding(
            get: { preferences.weeklyRecapEnabled },
            set: { isOn in
                preferences.weeklyRecapEnabled = isOn
                requestThenReschedule(isOn)
            }
        )
    }

    private var workoutDayEnabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.workoutDayReminderEnabled },
            set: { isOn in
                preferences.workoutDayReminderEnabled = isOn
                requestThenReschedule(isOn)
            }
        )
    }

    private func requestThenReschedule(_ isOn: Bool) {
        Task {
            await permission.toggled(on: isOn)
            reschedule()
        }
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { preferences.reminderHour },
            set: { preferences.reminderHour = $0; reschedule() }
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
