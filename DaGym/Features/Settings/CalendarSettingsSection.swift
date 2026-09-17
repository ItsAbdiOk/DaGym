import GymCore
import SwiftUI

/// Settings › Calendar & sync, first group: the schedule-to-Calendar toggle, the start hour, and
/// what the last sync refused to do.
struct CalendarSettingsSection: View {
    @Environment(Preferences.self) private var preferences
    @Environment(WorkoutStore.self) private var store
    /// What the last calendar sync refused to do, shown under the card — the same message
    /// `ScheduleView` shows. Nil when the last sync was fine (or never ran).
    @State private var syncProblem: String?

    var body: some View {
        SettingsSection {
            SettingsToggleRow(label: "Add schedule to Calendar", isOn: calendarSyncBinding)
            SettingsDivider()
            SettingsRow(label: "Start time") {
                Stepper(value: binding(\.scheduledStartHour), in: 0...23) {
                    Text(startHourLabel).font(DGFont.subhead).foregroundStyle(DGColor.ink3).monospacedDigit()
                }
                .accessibilityLabel("Start time")
                .accessibilityValue(startHourLabel)
            }
        }
        if let message = calendarProblemMessage {
            SettingsNote(text: message, tint: DGColor.danger)
        }
    }

    /// Wraps `calendarSyncEnabled` so turning it on kicks off an immediate sync (turning it off
    /// just stops future syncs — already-created events are left alone).
    private var calendarSyncBinding: Binding<Bool> {
        Binding(
            get: { preferences.calendarSyncEnabled },
            set: { enabled in
                preferences.calendarSyncEnabled = enabled
                syncProblem = nil
                if enabled { syncCalendarNow() }
            }
        )
    }

    /// `CalendarSyncCoordinator` owns the serialising chain (this toggle and a schedule edit
    /// could otherwise sync concurrently over the same event ids) and reports a refusal instead
    /// of swallowing it behind a `try?` — which used to leave the toggle switched on while every
    /// sync silently failed. A refusal also turns `calendarSyncEnabled` back off.
    private func syncCalendarNow() {
        guard !LaunchFlags.isTesting else { return }
        Task {
            let outcome = await CalendarSyncCoordinator.sync(store: store, preferences: preferences)
            syncProblem = outcome.problemMessage
        }
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter
    }()

    /// Read twice per render (label and accessibility value), so the formatter is hoisted.
    private var startHourLabel: String {
        var components = DateComponents()
        components.hour = preferences.scheduledStartHour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return Self.hourFormatter.string(from: date)
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }

    /// The toggle's own sync result first; otherwise whatever the last launch / foreground
    /// sync recorded on `CalendarSyncCoordinator.status`, which no view awaits. `status` is
    /// `@Observable`, so reading it from `body` re-renders the card when it changes.
    private var calendarProblemMessage: String? {
        syncProblem ?? CalendarSyncCoordinator.status.problemMessage
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            SettingsPage(title: "Calendar & sync") { CalendarSettingsSection() }
        }
        .environment(Preferences())
        .environment(store)
    }
}
