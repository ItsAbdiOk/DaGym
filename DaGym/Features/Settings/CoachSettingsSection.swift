import SwiftUI

/// Settings › Coach: the on-device AI status line, the switch that lets the coach use Apple's
/// on-device model at all, and the privacy note, then the cloud coach's own group
/// (`CoachChatSettingsCard`: key, model, consent, what's sent). Toggling re-runs
/// `CoachServices.refresh`, so the status line and every coach screen pick up the change at once.
struct CoachSettingsSection: View {
    @Environment(Preferences.self) private var preferences
    @Environment(CoachServices.self) private var coach

    var body: some View {
        SettingsSection(
            note: "The coach's debriefs, program builder, review and answers use Apple's on-device "
                + "model when it's available. It runs entirely on your iPhone; nothing is sent "
                + "anywhere. Off, the same features use fixed rules instead."
        ) {
            Text(coach.statusLine)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, DGSpace.s3)
                .accessibilityIdentifier(A11yID.coachStatus)
            SettingsDivider()
            SettingsToggleRow(label: "Use on-device AI", isOn: enabledBinding)
        }
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Cloud coach").dgLabel()
                .padding(.horizontal, DGSpace.s1)
                .padding(.top, DGSpace.s3)
            CoachChatSettingsCard()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.onDeviceCoachEnabled },
            set: {
                preferences.onDeviceCoachEnabled = $0
                coach.refresh(preferences: preferences)
            }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsPage(title: "Coach") { CoachSettingsSection() }
    }
    .environment(Preferences())
    .environment(CoachServices.make(preferences: Preferences()))
}
