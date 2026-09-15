import GymCore
import SwiftUI

/// Settings — a list of section cards (units, effort, rest timer, training, reminders, …)
/// plus the About card. Every control binds directly to `Preferences`, the single
/// persisted source of truth (see `DaGym/Design/UnitEnvironment.swift`).
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var showingAcknowledgements = false
    @State private var showingPrivacyPolicy = false

    var body: some View {
        ZStack {
            AmbientWash()
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpace.s6) {
                    header
                    UnitsSettingsSection()
                    EffortSettingsSection()
                    RestTimerSettingsSection()
                    TrainingSettingsSection()
                    RemindersSettingsSection()
                    VoiceSettingsSection()
                    CoachSettingsSection()
                    DisplaySettingsSection()
                    CalendarSettingsSection()
                    ICloudSettingsSection()
                    DataSettingsSection()
                    ImportSettingsSection()
                    EquipmentSettingsSection()
                    AppleHealthSettingsCard()
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
                Image(systemName: "chevron.right").accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
        }
        .buttonStyle(.dgRow)
    }

    private var privacyPolicyRow: some View {
        Button { showingPrivacyPolicy = true } label: {
            SettingsRow(label: "Privacy") {
                Image(systemName: "chevron.right").accessibilityHidden(true)
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

}

/// A labeled "SECTION" title above a `.dgCard()` of hairline-separated rows. Not `private`:
/// the section files alongside reuse this and `SettingsRow`/`SettingsDivider` below for the
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
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
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

/// Hairline separator between rows, indented to align with row text. The one divider for every
/// Settings card (`DisplaySettingsSection`, `RemindersSettingsSection`, `HealthSettingsView`
/// included) — it used to exist four times over.
struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
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
