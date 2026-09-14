import GymCore
import SwiftUI

/// Settings — units, effort scale, rest timer, training defaults, display
/// and about. Every control binds directly to `Preferences`, the single
/// persisted source of truth (see `DaGym/Design/UnitEnvironment.swift`).
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingAcknowledgements = false
    @State private var showingPrivacyPolicy = false
    /// What the last calendar sync refused to do, shown under the Calendar card — the same
    /// message `ScheduleView` shows. Nil when the last sync was fine (or never ran).
    @State private var syncProblem: String?
    /// The weekly-goal stepper needs its own reschedule (S14/F14): `RemindersSettingsSection`'s
    /// three bindings reschedule on change, but the notification body embeds
    /// `weeklyGoal - thisWeekCount` at schedule time, so a goal edit here must reschedule too or
    /// Saturday's push keeps saying the old number.
    private let notificationScheduler = TrainingNotificationScheduler()

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    unitsCard
                    EffortSettingsSection()
                    restTimerCard
                    trainingCard
                    RemindersSettingsSection()
                    VoiceSettingsSection()
                    DisplaySettingsSection()
                    calendarCard
                    ICloudSettingsSection()
                    DataSettingsSection()
                    ImportSettingsSection()
                    EquipmentSettingsSection()
                    AppleHealthSettingsCard()
                    #if DEBUG
                    DeveloperSettingsSection()
                    #endif
                    aboutCard
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showingAcknowledgements) { AcknowledgementsView() }
        .sheet(isPresented: $showingPrivacyPolicy) { PrivacyPolicyView() }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "xmark", accessibilityLabel: "Close") { dismiss() }
        }
    }

    private var unitsCard: some View {
        SettingsSection(title: "Units") {
            SettingsRow(label: "Weight unit") {
                Picker("Weight unit", selection: binding(\.weightUnit)) {
                    Text("KG").tag(WeightUnit.kg)
                    Text("LB").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                .tint(DGColor.coral)
                .frame(width: 120)
            }
        }
    }

    private var restTimerCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            restTimerRows
            Text("Default rest applies to every exercise unless you set its own rest timer in"
                + " Exercise Detail. \"Off\" turns the rest timer off completely — no countdown, no alert.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var restTimerRows: some View {
        SettingsSection(title: "Rest Timer") {
            SettingsRow(label: "Default rest") {
                Stepper(value: binding(\.defaultRestSeconds), in: 0...300, step: 15) {
                    Text(restTimerLabel).font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                }
            }
            SettingsDivider()
            SettingsRow(label: "Rest-pause rest") {
                Stepper(value: binding(\.restPauseSeconds), in: 5...60, step: 5) {
                    Text(WorkoutSession.clock(preferences.restPauseSeconds))
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                }
            }
            SettingsDivider()
            SettingsRow(label: "Sound") {
                Toggle("", isOn: binding(\.restSound)).tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Play on silent") {
                Toggle("", isOn: binding(\.playRestSoundOnSilent)).tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Haptics") {
                Toggle("", isOn: binding(\.restHaptics)).tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Screen flash") {
                Toggle("", isOn: binding(\.restScreenFlash)).tint(DGColor.coral).labelsHidden()
            }
        }
    }

    /// "Off" at 0 seconds (features #20); otherwise the usual `m:ss` clock.
    private var restTimerLabel: String {
        preferences.defaultRestSeconds == 0 ? "Off" : WorkoutSession.clock(preferences.defaultRestSeconds)
    }

    private var trainingCard: some View {
        SettingsSection(title: "Training") {
            TrainingGoalRow(onApply: {
                preferences.applyTrainingGoalDefaults()
                notificationScheduler.rescheduleAll(store: store, preferences: preferences)
            })
            SettingsDivider()
            SettingsRow(label: "Weekly goal") {
                Stepper(value: weeklyGoalBinding, in: 1...7) {
                    Text("\(preferences.weeklyGoal)").font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                }
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
                Toggle("", isOn: binding(\.weighInBeforeWorkout)).tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            CheckInCardButton()
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            calendarRows
            if let message = calendarProblemMessage {
                Text(message).font(DGFont.footnote).foregroundStyle(DGColor.danger)
            }
        }
    }

    private var calendarRows: some View {
        SettingsSection(title: "Calendar") {
            SettingsRow(label: "Add my schedule to Calendar") {
                Toggle("", isOn: calendarSyncBinding).tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Start time") {
                Stepper(value: binding(\.scheduledStartHour), in: 0...23) {
                    Text(startHourLabel).font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                }
            }
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

    private var startHourLabel: String {
        var components = DateComponents()
        components.hour = preferences.scheduledStartHour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("About").dgLabel()
            VStack(spacing: 0) {
                SettingsRow(label: "Version") {
                    Text(Self.versionText).font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                }
                SettingsDivider()
                acknowledgementsRow
                SettingsDivider()
                privacyPolicyRow
            }
            .dgCard(padding: 0)
            Text(preferences.iCloudSyncEnabled ? "Synced with your iCloud" : "Data stays on your device")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var acknowledgementsRow: some View {
        Button { showingAcknowledgements = true } label: {
            SettingsRow(label: "Acknowledgements") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
        }
        .buttonStyle(.dgRow)
    }

    private var privacyPolicyRow: some View {
        Button { showingPrivacyPolicy = true } label: {
            SettingsRow(label: "Privacy") {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
        }
        .buttonStyle(.dgRow)
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }

    /// "This week" moving changes which days the goal-at-risk and recap notifications belong to,
    /// so the pending ones have to be rebuilt — otherwise the change only lands on next launch.
    private var weekStartsMondayBinding: Binding<Bool> {
        Binding(
            get: { preferences.weekStartsMonday },
            set: {
                preferences.weekStartsMonday = $0
                notificationScheduler.rescheduleAll(store: store, preferences: preferences)
                WidgetSnapshotWriter.refresh(store: store, preferences: preferences)
            }
        )
    }

    private var weeklyGoalBinding: Binding<Int> {
        Binding(
            get: { preferences.weeklyGoal },
            set: {
                preferences.weeklyGoal = $0
                notificationScheduler.rescheduleAll(store: store, preferences: preferences)
            }
        )
    }
}

/// A labeled "SECTION" title above a `.dgCard()` of hairline-separated rows. Not `private`:
/// `AppleHealthSettingsCard.swift` reuses this and `SettingsRow`/`SettingsDivider` below for the
/// same visual language — `private` is file-scoped in Swift, so a different file can't see it.
struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text(title).dgLabel()
            VStack(spacing: 0) { content }
                .dgCard(padding: 0)
        }
    }
}

/// One "label … trailing control" row inside a settings card.
struct SettingsRow<Trailing: View>: View {
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

/// The "Goal" row: the onboarding answer, made editable and made real. Changing it calls back so
/// the caller can re-apply that goal's rest length and weekly session count — the two numbers its
/// own subtitle promises — rather than leaving the answer as a stored string nobody reads.
struct TrainingGoalRow: View {
    var onApply: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingsRow(label: "Goal") {
                Picker("Goal", selection: goalBinding) {
                    ForEach(Preferences.TrainingGoal.allCases, id: \.self) { goal in
                        Text(goal.title).tag(goal)
                    }
                }
                .pickerStyle(.menu)
                .tint(DGColor.coral)
            }
            Text(preferences.trainingGoal.detail)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
                .padding(.horizontal, DGSpace.s5)
                .padding(.bottom, DGSpace.s3)
        }
    }

    private var goalBinding: Binding<Preferences.TrainingGoal> {
        Binding(
            get: { preferences.trainingGoal },
            set: {
                preferences.trainingGoal = $0
                onApply()
            }
        )
    }
}

/// Hairline separator between rows, indented to align with row text.
struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

extension SettingsView {
    /// The toggle's own sync result first; otherwise whatever the last launch / foreground
    /// sync recorded on `CalendarSyncCoordinator.status`, which no view awaits. `status` is
    /// `@Observable`, so reading it from `body` re-renders the calendar card when it changes.
    fileprivate var calendarProblemMessage: String? {
        syncProblem ?? CalendarSyncCoordinator.status.problemMessage
    }
}

#Preview {
    if let store = PreviewStore.make() {
        let preferences = Preferences()
        return AnyView(
            SettingsView()
                .environment(preferences)
                .environment(store)
                .environment(HealthInsightsService(
                    healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                ))
        )
    }
    return AnyView(EmptyView())
}
