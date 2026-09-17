import SwiftUI

/// Settings › About: version, acknowledgements and the privacy policy.
struct AboutSettingsSection: View {
    @Environment(Preferences.self) private var preferences
    @State private var showingAcknowledgements = false
    @State private var showingPrivacyPolicy = false

    var body: some View {
        SettingsSection(
            note: preferences.iCloudSyncEnabled ? "Synced with your iCloud." : "Data stays on your device."
        ) {
            SettingsValueRow(label: "Version", value: Self.versionText)
            SettingsDivider()
            SettingsLinkRow(label: "Acknowledgements") { showingAcknowledgements = true }
            SettingsDivider()
            SettingsLinkRow(label: "Privacy policy") { showingPrivacyPolicy = true }
        }
        .sheet(isPresented: $showingAcknowledgements) { AcknowledgementsView() }
        .sheet(isPresented: $showingPrivacyPolicy) { PrivacyPolicyView() }
    }

    /// "1.4.2 (87)" for the Version row.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(shortVersion) (\(build))"
    }

    /// Just the marketing version, for the index row.
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

#Preview {
    NavigationStack {
        SettingsPage(title: "About") { AboutSettingsSection() }
    }
    .environment(Preferences())
}
