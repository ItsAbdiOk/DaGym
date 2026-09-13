import GymCore
import SwiftUI

/// Settings — units, effort scale, rest timer, training defaults, display
/// and about. Every control binds directly to `Preferences`, the single
/// persisted source of truth (see `DaGym/Design/UnitEnvironment.swift`).
struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var showingAcknowledgements = false

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
                    displayCard
                    aboutCard
                }
                .padding(.horizontal, DGSpace.s4)
                .padding(.top, DGSpace.s3)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showingAcknowledgements) { AcknowledgementsView() }
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
                Stepper(value: binding(\.weeklyGoal), in: 1...7) {
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
            }
            .dgCard(padding: 0)
            Text("Data stays on your device")
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
    SettingsView()
        .environment(Preferences())
}
