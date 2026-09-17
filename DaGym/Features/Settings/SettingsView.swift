import GymCore
import SwiftUI

/// Settings — the redesign's index page: four kickers (Logging, Plan, Coach & display, Your
/// data) of icon rows, each showing its current value and pushing its own page. Every page
/// binds directly to `Preferences`, the single persisted source of truth (see
/// `DaGym/Design/UnitEnvironment.swift`).
///
/// Pushed from the You hub (`YouDestination.settings`), so it registers its
/// `navigationDestination` on the hub's stack and adds no `NavigationStack` of its own. A few
/// callers still present it as a sheet (the coach's "open Settings" action, screenshot mode);
/// those pass `standalone: true` and get their own stack plus a Done button.
struct SettingsView: View {
    var standalone = false

    @Environment(Preferences.self) private var preferences
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if standalone {
            NavigationStack {
                index.toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.tint(DGColor.coralText)
                    }
                }
            }
        } else {
            index
        }
    }

    private var index: some View {
        SettingsPage(title: "Settings") {
            SettingsSection(title: "Logging") {
                row(.units, value: "\(preferences.unitSymbol) · \(preferences.distanceUnit.symbol)")
                SettingsDivider()
                row(.effort, value: effortValue)
                SettingsDivider()
                row(.rest, value: RestTimerSettingsSection.clock(preferences.defaultRestSeconds))
                SettingsDivider()
                row(.workout, value: preferences.workoutLayout.title)
            }
            SettingsSection(title: "Plan") {
                row(.training, value: preferences.trainingGoal.title)
                SettingsDivider()
                row(.reminders, value: RemindersSettingsSection.hourLabel(preferences.reminderHour))
                SettingsDivider()
                row(.voice, value: nil)
            }
            SettingsSection(title: "Coach & display") {
                row(.coach, value: preferences.onDeviceCoachEnabled ? "On" : "Off")
                SettingsDivider()
                row(.display, value: preferences.appearance.rawValue.capitalized)
                SettingsDivider()
                row(.sync, value: preferences.iCloudSyncEnabled ? "On" : "Off")
                SettingsDivider()
                row(.health, value: preferences.healthWriteWorkouts ? "On" : "Off")
            }
            SettingsSection(
                title: "Your data",
                note: "Everything lives on your device. iCloud sync is optional and chats never leave "
                    + "the app."
            ) {
                row(.equipment, value: store.equipmentProfiles().first(where: \.isActive)?.name)
                SettingsDivider()
                row(.data, value: nil)
                SettingsDivider()
                row(.about, value: AboutSettingsSection.shortVersion)
            }
        }
        .navigationDestination(for: SettingsDestination.self) { destination in
            destination.screen
        }
    }

    private var effortValue: String {
        preferences.effortTrackingEnabled ? preferences.effortScale.rawValue.uppercased() : "Off"
    }

    private func row(_ destination: SettingsDestination, value: String?) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: DGSpace.s3) {
                SettingsIconSquare(symbol: destination.symbol)
                Text(destination.title).font(DGFont.subhead).foregroundStyle(DGColor.ink1)
                Spacer(minLength: DGSpace.s2)
                if let value {
                    Text(value).font(DGFont.subhead).foregroundStyle(DGColor.ink3).lineLimit(1)
                }
                SettingsChevron()
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
        .accessibilityLabel(value.map { "\(destination.title): \($0)" } ?? destination.title)
        .accessibilityIdentifier(destination.accessibilityID)
    }
}

/// The fourteen Settings pages, in index order. Each is one push deep from the index.
enum SettingsDestination: Hashable, CaseIterable {
    case units, effort, rest, workout, training, reminders, voice
    case coach, display, sync, health, equipment, data, about

    var title: String {
        switch self {
        case .units: "Units"
        case .effort: "Effort"
        case .rest: "Rest timer"
        case .workout: "Workout"
        case .training: "Training"
        case .reminders: "Reminders"
        case .voice: "Voice logging"
        case .coach: "Coach"
        case .display: "Display"
        case .sync: "Calendar & sync"
        case .health: "Apple Health"
        case .equipment: "Equipment profiles"
        case .data: "Data & backup"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .units: "scalemass.fill"
        case .effort: "gauge.with.needle.fill"
        case .rest: "timer"
        case .workout: "dumbbell.fill"
        case .training: "target"
        case .reminders: "bell.fill"
        case .voice: "mic.fill"
        case .coach: "bubble.left.fill"
        case .display: "circle.lefthalf.filled"
        case .sync: "calendar"
        case .health: "heart.fill"
        case .equipment: "shippingbox.fill"
        case .data: "externaldrive.fill"
        case .about: "info.circle.fill"
        }
    }

    var accessibilityID: String { "settings.\(String(describing: self))" }

    @ViewBuilder @MainActor
    var screen: some View {
        switch self {
        case .units: SettingsPage(title: title) { UnitsSettingsSection() }
        case .effort: SettingsPage(title: title) { EffortSettingsSection() }
        case .rest: SettingsPage(title: title) { RestTimerSettingsSection() }
        case .workout: SettingsPage(title: title) { WorkoutSettingsSection() }
        case .training: SettingsPage(title: title) { TrainingSettingsSection() }
        case .reminders: SettingsPage(title: title) { RemindersSettingsSection() }
        case .voice: SettingsPage(title: title) { VoiceSettingsSection() }
        case .coach: SettingsPage(title: title) { CoachSettingsSection() }
        case .display: SettingsPage(title: title) { DisplaySettingsSection() }
        case .sync: SettingsPage(title: title) { CalendarSettingsSection(); ICloudSettingsSection() }
        case .health: HealthSettingsView(pushed: true)
        case .equipment: EquipmentProfilesScreen()
        case .data:
            SettingsPage(title: title) {
                DataSettingsSection()
                ImportSettingsSection()
                ResetSettingsSection()
            }
        case .about: SettingsPage(title: title) { AboutSettingsSection() }
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        let preferences = Preferences()
        return AnyView(
            NavigationStack { SettingsView() }
                .environment(preferences)
                .environment(store)
                .environment(HealthInsightsService(
                    healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                ))
        )
    }
    return AnyView(EmptyView())
}
