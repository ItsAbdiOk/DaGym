import SwiftUI

/// Settings › Calendar & sync, second group: toggle CloudKit sync and show whether the device
/// is actually signed in (plan.md §6.3). The toggle only takes effect on next launch — the
/// store's CloudKit configuration is fixed when `ModelContainer.dagym(...)` opens it — hence
/// the note.
struct ICloudSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        SettingsSection(note: "iCloud changes apply next launch.") {
            SettingsToggleRow(label: "iCloud sync", sub: statusLine, isOn: syncBinding)
        }
    }

    private var syncBinding: Binding<Bool> {
        Binding(get: { preferences.iCloudSyncEnabled }, set: { preferences.iCloudSyncEnabled = $0 })
    }

    private var isSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var statusLine: String {
        guard preferences.iCloudSyncEnabled else { return "Local only" }
        return isSignedIn ? "Syncing via your iCloud" : "Local only — sign in to iCloud in Settings"
    }
}

#Preview {
    NavigationStack {
        SettingsPage(title: "Calendar & sync") { ICloudSettingsSection() }
    }
    .environment(Preferences())
}
