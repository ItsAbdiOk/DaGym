import SwiftUI

/// Settings › Voice logging: the two switches that decide what voice logging is allowed to do
/// on its own, each with its consequence spelled out under the label.
struct VoiceSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        SettingsSection(
            note: "Hold the mic in a workout and say “bench 72.5 for 8”, “rate that an 8”, “undo”, "
                + "or “what was last session?”."
        ) {
            SettingsToggleRow(
                label: "Log without confirming",
                sub: "Off: every set you say opens a card to check before it's logged. On: a set "
                    + "the phone heard clearly, with one weight and one rep count, is logged "
                    + "straight away — undo is always in the toast.",
                isOn: autoLogBinding
            )
            SettingsDivider()
            SettingsToggleRow(
                label: "Speak back on headphones",
                sub: "Only through headphones you're wearing — never out loud on a speaker.",
                isOn: speakBackBinding
            )
        }
    }

    private var autoLogBinding: Binding<Bool> {
        Binding(get: { preferences.voiceAutoLogEnabled }, set: { preferences.voiceAutoLogEnabled = $0 })
    }

    private var speakBackBinding: Binding<Bool> {
        Binding(
            get: { preferences.voiceSpeakBackOnHeadphones },
            set: { preferences.voiceSpeakBackOnHeadphones = $0 }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsPage(title: "Voice logging") { VoiceSettingsSection() }
    }
    .environment(Preferences())
}
