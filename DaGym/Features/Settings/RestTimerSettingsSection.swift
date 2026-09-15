import GymCore
import SwiftUI

/// The Settings "REST TIMER" card: default rest, rest-pause rest and the four alert toggles,
/// bound directly to `Preferences`.
struct RestTimerSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            rows
            Text("Default rest applies to every exercise unless you set its own rest timer in"
                + " Exercise Detail. \"Off\" turns the rest timer off completely — no countdown, no alert.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var rows: some View {
        SettingsSection(title: "Rest Timer") {
            SettingsRow(label: "Default rest") {
                Stepper(value: binding(\.defaultRestSeconds), in: 0...300, step: 15) {
                    Text(restTimerLabel).font(DGFont.subhead).foregroundStyle(DGColor.ink3)
                }
                .accessibilityLabel("Default rest")
                .accessibilityValue(restTimerLabel)
            }
            SettingsDivider()
            SettingsRow(label: "Rest-pause rest") {
                Stepper(value: binding(\.restPauseSeconds), in: 5...60, step: 5) {
                    Text(WorkoutSession.clock(preferences.restPauseSeconds))
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                }
                .accessibilityLabel("Rest-pause rest")
                .accessibilityValue(WorkoutSession.clock(preferences.restPauseSeconds))
            }
            SettingsDivider()
            SettingsRow(label: "Sound") {
                Toggle("Sound", isOn: binding(\.restSound)).tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Play on silent") {
                Toggle("Play on silent", isOn: binding(\.playRestSoundOnSilent))
                    .tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Haptics") {
                Toggle("Haptics", isOn: binding(\.restHaptics)).tint(DGColor.coral).labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Screen flash") {
                Toggle("Screen flash", isOn: binding(\.restScreenFlash)).tint(DGColor.coral).labelsHidden()
            }
        }
    }

    /// "Off" at 0 seconds (features #20); otherwise the usual `m:ss` clock.
    private var restTimerLabel: String {
        preferences.defaultRestSeconds == 0 ? "Off" : WorkoutSession.clock(preferences.defaultRestSeconds)
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }
}

#Preview {
    ScrollView {
        RestTimerSettingsSection()
            .padding(DGSpace.s4)
    }
    .environment(Preferences())
    .background(AmbientWash())
}
