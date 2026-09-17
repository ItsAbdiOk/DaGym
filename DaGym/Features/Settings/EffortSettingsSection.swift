import GymCore
import SwiftUI

/// Settings › Effort: an on/off toggle (OpenGym parity, features "Adopt now" #18) that hides
/// the RIR/RPE scale picker and the effort column everywhere else in the app, plus a "What are
/// RPE and RIR?" help sheet.
struct EffortSettingsSection: View {
    @Environment(Preferences.self) private var preferences
    @State private var showingHelp = false

    var body: some View {
        SettingsSection {
            SettingsToggleRow(label: "Track effort", isOn: trackingBinding)
            if preferences.effortTrackingEnabled {
                SettingsDivider()
                SettingsRow(label: "Scale") {
                    SettingsSegment(
                        label: "Effort scale", selection: scaleBinding,
                        options: [(Effort.Scale.rpe, "RPE"), (Effort.Scale.rir, "RIR")]
                    )
                }
                SettingsDivider()
                SettingsLinkRow(label: "What are RPE and RIR?") { showingHelp = true }
            }
        }
        .sheet(isPresented: $showingHelp) { EffortHelpSheet() }
    }

    private var trackingBinding: Binding<Bool> {
        Binding(get: { preferences.effortTrackingEnabled }, set: { preferences.effortTrackingEnabled = $0 })
    }

    private var scaleBinding: Binding<Effort.Scale> {
        Binding(get: { preferences.effortScale }, set: { preferences.effortScale = $0 })
    }
}

#Preview {
    NavigationStack {
        SettingsPage(title: "Effort") { EffortSettingsSection() }
    }
    .environment(Preferences())
}
