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
    @State private var showingHealthSettings = false
    @State private var showingBodyweightSheet = false
    @State private var eventStore: EventStoring = EventKitStore()
    @State private var syncTask: Task<Void, Never>?
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
                    effortCard
                    restTimerCard
                    trainingCard
                    RemindersSettingsSection()
                    displayCard
                    calendarCard
                    ICloudSettingsSection()
                    DataSettingsSection()
                    ImportSettingsSection()
                    EquipmentSettingsSection()
                    healthCard
                    aboutCard
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showingAcknowledgements) { AcknowledgementsView() }
        .sheet(isPresented: $showingHealthSettings) { HealthSettingsView() }
        .sheet(isPresented: $showingBodyweightSheet) { BodyweightSheet() }
    }

    private var healthCard: some View {
        SettingsSection(title: "Apple Health") {
            Button { showingHealthSettings = true } label: {
                SettingsRow(label: "Apple Health") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .buttonStyle(.plain)
            SettingsDivider()
            Button { showingBodyweightSheet = true } label: {
                SettingsRow(label: "Bodyweight") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(DGFont.title1)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "xmark") { dismiss() }
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

    private var effortCard: some View {
        SettingsSection(title: "Effort") {
            SettingsRow(label: "Scale") {
                Picker("Effort scale", selection: binding(\.effortScale)) {
                    Text("RPE").tag(Effort.Scale.rpe)
                    Text("RIR").tag(Effort.Scale.rir)
                }
                .pickerStyle(.segmented)
                .tint(DGColor.coral)
                .frame(width: 120)
            }
        }
    }

    private var restTimerCard: some View {
        SettingsSection(title: "Rest Timer") {
            SettingsRow(label: "Default rest") {
                Stepper(value: binding(\.defaultRestSeconds), in: 30...300, step: 15) {
                    Text(WorkoutSession.clock(preferences.defaultRestSeconds))
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                }
            }
            SettingsDivider()
            SettingsRow(label: "Sound") {
                Toggle("", isOn: binding(\.restSound)).tint(DGColor.coral).labelsHidden()
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

    private var trainingCard: some View {
        SettingsSection(title: "Training") {
            SettingsRow(label: "Weekly goal") {
                Stepper(value: weeklyGoalBinding, in: 1...7) {
                    Text("\(preferences.weeklyGoal)").font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                }
            }
            SettingsDivider()
            SettingsRow(label: "Week starts") {
                Picker("Week starts", selection: binding(\.weekStartsMonday)) {
                    Text("MON").tag(true)
                    Text("SUN").tag(false)
                }
                .pickerStyle(.segmented)
                .tint(DGColor.coral)
                .frame(width: 120)
            }
        }
    }

    private var displayCard: some View {
        SettingsSection(title: "Display") {
            SettingsRow(label: "Keep screen awake") {
                Toggle("", isOn: binding(\.keepScreenAwake)).tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Lock progress photos") {
                Toggle("", isOn: binding(\.lockPhotos)).tint(DGColor.coral).labelsHidden()
            }
        }
    }

    private var calendarCard: some View {
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
                if enabled { syncCalendarNow() }
            }
        )
    }

    private func syncCalendarNow() {
        let schedule = store.schedule()
        let routines = store.routines()
        let hour = preferences.scheduledStartHour
        // Serialised so a toggle flicked twice can't run two syncs over the same event IDs.
        let previous = syncTask
        syncTask = Task {
            await previous?.value
            let service = CalendarSyncService(eventStore: eventStore)
            let request = ScheduleSyncRequest(
                schedule: schedule, routines: routines, startDate: Date(), defaultStartHour: hour,
                existingEventIDs: store.scheduleEventIDs()
            )
            guard let updated = try? await service.sync(request) else { return }
            store.saveScheduleEventIDs(updated)
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
        .buttonStyle(.plain)
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

/// A labeled "SECTION" title above a `.dgCard()` of hairline-separated rows.
private struct SettingsSection<Content: View>: View {
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
private struct SettingsRow<Trailing: View>: View {
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

/// Hairline separator between rows, indented to align with row text.
private struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

#Preview {
    if let store = PreviewStore.make() {
        return AnyView(
            SettingsView()
                .environment(Preferences())
                .environment(store)
        )
    }
    return AnyView(EmptyView())
}
