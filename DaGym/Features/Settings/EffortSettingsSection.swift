import GymCore
import SwiftUI

/// The Settings "Effort" section: an on/off toggle (OpenGym parity, features "Adopt now" #18)
/// that hides the RIR/RPE scale picker and the effort column everywhere else in the app, plus a
/// "What are RIR and RPE?" help sheet. Split out of `SettingsView` to keep that struct's body
/// under SwiftLint's `type_body_length` limit — same pattern as `DisplaySettingsSection`.
struct EffortSettingsSection: View {
    @Environment(Preferences.self) private var preferences
    @State private var showingHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Effort").dgLabel()
            VStack(spacing: 0) {
                row(label: "Track effort") {
                    Toggle("", isOn: trackingBinding).tint(DGColor.coral).labelsHidden()
                }
                if preferences.effortTrackingEnabled {
                    EffortSectionDivider()
                    row(label: "Scale") {
                        Picker("Effort scale", selection: scaleBinding) {
                            Text("RPE").tag(Effort.Scale.rpe)
                            Text("RIR").tag(Effort.Scale.rir)
                        }
                        .pickerStyle(.segmented)
                        .tint(DGColor.coral)
                        .frame(width: 120)
                    }
                    EffortSectionDivider()
                    Button { showingHelp = true } label: {
                        row(label: "What are RIR and RPE?") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DGColor.ink4)
                        }
                    }
                    .buttonStyle(.dgRow)
                }
            }
            .dgCard(padding: 0)
        }
        .sheet(isPresented: $showingHelp) { EffortHelpSheet() }
    }

    private func row<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            trailing()
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 52)
    }

    private var trackingBinding: Binding<Bool> {
        Binding(get: { preferences.effortTrackingEnabled }, set: { preferences.effortTrackingEnabled = $0 })
    }

    private var scaleBinding: Binding<Effort.Scale> {
        Binding(get: { preferences.effortScale }, set: { preferences.effortScale = $0 })
    }
}

private struct EffortSectionDivider: View {
    var body: some View {
        Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
    }
}

#Preview {
    ScrollView {
        EffortSettingsSection()
            .padding(DGSpace.s4)
    }
    .environment(Preferences())
    .background(AmbientWash())
}
