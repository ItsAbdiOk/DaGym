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
    /// `@State`, not a plain stored property: `SettingsView.body` rebuilds this section on every
    /// stepper tap up there, and a stored property would hand each rebuild a fresh, unread
    /// `.notDetermined` state — so the "Notifications are off" row vanished the moment the lifter
    /// touched anything else in Settings, and `.task` never re-ran to bring it back.
    @State private var permission: ReminderPermissionState

    @Environment(Preferences.self) private var preferences
    @Environment(WorkoutStore.self) private var store

    /// `static`: a stored property was rebuilt on every `SettingsView` render.
    private static let scheduler = TrainingNotificationScheduler()
    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter
    }()

    /// The default `permission`. One app-wide instance rather than a fresh `@Observable` per
    /// `SettingsView` render — `@State` keeps only the first anyway, and the status it holds is
    /// the device's, not this view's. Not private: a default argument is evaluated at the call
    /// site, so a `private` static can't be one.
    static let sharedPermission = ReminderPermissionState()

    /// Injectable so `FeatureSettingsTests` can drive the granted/denied/not-determined states.
    init(permission: ReminderPermissionState = RemindersSettingsSection.sharedPermission) {
        _permission = State(initialValue: permission)
    }

    var body: some View {
        SettingsSection(
            note: "A Saturday nudge when the weekly goal is at risk, a Sunday recap, and a reminder"
                + " on each day you've scheduled a routine."
        ) {
            SettingsToggleRow(label: "Streak reminders", sub: "Saturday", isOn: streakBinding)
            SettingsDivider()
            SettingsToggleRow(label: "Weekly recap", sub: "Sunday", isOn: recapBinding)
            SettingsDivider()
            SettingsRow(label: "Reminder time") {
                Stepper(value: hourBinding, in: 0...23) {
                    Text(hourLabel).font(DGFont.subhead).foregroundStyle(DGColor.ink3).monospacedDigit()
                }
                .accessibilityLabel("Reminder time")
                .accessibilityValue(hourLabel)
            }
            SettingsDivider()
            SettingsToggleRow(label: "Workout day reminder", isOn: workoutDayEnabledBinding)
            if preferences.workoutDayReminderEnabled {
                SettingsDivider()
                SettingsRow(label: "Workout day time") {
                    Stepper(value: workoutDayHourBinding, in: 0...23) {
                        Text(workoutDayHourLabel)
                            .font(DGFont.subhead)
                            .foregroundStyle(DGColor.ink3)
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Workout day time")
                    .accessibilityValue(workoutDayHourLabel)
                }
            }
            if showsDeniedRow {
                SettingsDivider()
                deniedRow
            }
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
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink1)
                        .multilineTextAlignment(.leading)
                    Text("These reminders can't be delivered until you turn them back on.")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink4)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: DGSpace.s2)
                SettingsChevron()
            }
            .padding(.horizontal, 15)
            .padding(.vertical, DGSpace.s3)
            .frame(minHeight: 46)
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
        Self.scheduler.rescheduleAll(store: store, preferences: preferences)
    }

    private var hourLabel: String { Self.hourLabel(preferences.reminderHour) }
    private var workoutDayHourLabel: String { Self.hourLabel(preferences.workoutDayReminderHour) }

    /// The index row shows the reminder hour the same way, so this is not private.
    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return hourFormatter.string(from: date)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        return AnyView(
            NavigationStack {
                SettingsPage(title: "Reminders") { RemindersSettingsSection() }
            }
            .environment(Preferences())
            .environment(store)
        )
    }
    return AnyView(EmptyView())
}
