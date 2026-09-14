import SwiftUI

/// The Settings "Voice" section: the two switches that decide what voice logging is allowed to do
/// on its own. Split out of `SettingsView` to keep that struct's body under SwiftLint's
/// `type_body_length` limit — same pattern as `DisplaySettingsSection`.
struct VoiceSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Voice").dgLabel()
            VStack(spacing: 0) {
                row(label: "Log without confirming", isOn: autoLogBinding)
                VoiceSectionDivider()
                caption(
                    "Off: every set you say opens a card to check before it's logged. On: a set " +
                    "the phone heard clearly, with one weight and one rep count, is logged " +
                    "straight away — undo is always in the toast."
                )
                VoiceSectionDivider()
                row(label: "Speak back on headphones", isOn: speakBackBinding)
                VoiceSectionDivider()
                caption("Only through headphones you're wearing — never out loud on a speaker.")
            }
            .dgCard(padding: 0)
        }
    }

    private func row(label: String, isOn: Binding<Bool>) -> some View {
        DGAdaptiveStack(verticalAlignment: .center, spacing: DGSpace.s2) {
            Text(label).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Toggle(label, isOn: isOn).tint(DGColor.coral).labelsHidden()
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(DGFont.subhead)
            .foregroundStyle(DGColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DGSpace.s5)
            .padding(.vertical, DGSpace.s3)
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

private struct VoiceSectionDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

#Preview {
    ScrollView {
        VoiceSettingsSection()
            .padding(DGSpace.s4)
    }
    .environment(Preferences())
    .background(AmbientWash())
}
