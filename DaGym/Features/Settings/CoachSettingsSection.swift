import SwiftUI

/// The Settings "Coach" section: the on-device AI status line, the switch that lets the coach
/// use Apple's on-device model at all, and the privacy note. Same layout as
/// `VoiceSettingsSection`. Toggling re-runs `CoachServices.refresh`, so the status line and
/// every coach screen pick up the change at once.
struct CoachSettingsSection: View {
    @Environment(Preferences.self) private var preferences
    @Environment(CoachServices.self) private var coach

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Coach").dgLabel()
            VStack(spacing: 0) {
                caption(coach.statusLine)
                    .accessibilityIdentifier(A11yID.coachStatus)
                CoachSectionDivider()
                row(label: "Use on-device AI", isOn: enabledBinding)
                CoachSectionDivider()
                caption(
                    "The coach's debriefs, program builder, review and answers use Apple's on-device "
                        + "model when it's available. It runs entirely on your iPhone; nothing is sent "
                        + "anywhere. Off, the same features use fixed rules instead."
                )
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

private struct CoachSectionDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

#Preview {
    ScrollView {
        CoachSettingsSection()
            .padding(DGSpace.s4)
    }
    .environment(Preferences())
    .environment(CoachServices.make(preferences: Preferences()))
    .background(AmbientWash())
}
