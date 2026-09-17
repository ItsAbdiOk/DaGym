import GymCore
import SwiftUI

/// Settings › Rest timer: default rest and rest-pause rest (steppers, so the value row still
/// edits in place), then the four alert toggles, bound directly to `Preferences`.
struct RestTimerSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        SettingsSection {
            SettingsRow(label: "Default rest") {
                Stepper(value: binding(\.defaultRestSeconds), in: 0...300, step: 15) {
                    Text(restTimerLabel).font(DGFont.subhead).foregroundStyle(DGColor.ink3).monospacedDigit()
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
                        .monospacedDigit()
                }
                .accessibilityLabel("Rest-pause rest")
                .accessibilityValue(WorkoutSession.clock(preferences.restPauseSeconds))
            }
        }
        SettingsSection(
            note: "Default rest applies to every exercise unless you set its own rest timer in"
                + " Exercise Detail. \"Off\" turns the rest timer off completely — no countdown, no alert."
        ) {
            SettingsToggleRow(label: "Sound", isOn: binding(\.restSound))
            SettingsDivider()
            SettingsToggleRow(label: "Play on silent", isOn: binding(\.playRestSoundOnSilent))
            SettingsDivider()
            SettingsToggleRow(label: "Haptics", isOn: binding(\.restHaptics))
            SettingsDivider()
            SettingsToggleRow(label: "Screen flash", isOn: binding(\.restScreenFlash))
        }
    }

    /// "Off" at 0 seconds (features #20); otherwise the usual `m:ss` clock.
    private var restTimerLabel: String { Self.clock(preferences.defaultRestSeconds) }

    /// The index row shows the same label, so it lives here rather than in both places.
    static func clock(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : WorkoutSession.clock(seconds)
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }
}

#Preview {
    NavigationStack {
        SettingsPage(title: "Rest timer") { RestTimerSettingsSection() }
    }
    .environment(Preferences())
}
