import SwiftUI

/// The Settings "iCloud" section: toggle CloudKit sync and show whether the device is actually
/// signed in (plan.md §6.3). The toggle only takes effect on next launch — the store's CloudKit
/// configuration is fixed when `ModelContainer.dagym(...)` opens it — hence the footnote.
struct ICloudSettingsSection: View {
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("iCloud").dgLabel()
            VStack(spacing: 0) {
                HStack {
                    Text("Sync with iCloud").font(DGFont.body).foregroundStyle(DGColor.ink1)
                    Spacer()
                    Toggle("", isOn: syncBinding).tint(DGColor.coral).labelsHidden()
                }
                .padding(.horizontal, DGSpace.s5)
                .frame(minHeight: 52)
            }
            .dgCard(padding: 0)
            Text(statusLine)
                .font(DGFont.footnote)
                .foregroundStyle(isSignedIn ? DGColor.ink4 : DGColor.warning)
            Text("Changes apply on next launch.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
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
    ScrollView {
        ICloudSettingsSection()
            .padding(DGSpace.s4)
    }
    .environment(Preferences())
    .background(AmbientWash())
}
