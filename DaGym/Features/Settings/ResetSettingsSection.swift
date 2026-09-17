import SwiftUI

/// Settings › Data & backup, last group: "Reset everything", behind `ResetAllDataSheet`'s typed
/// confirmation. Its own view (not a row of `DataSettingsSection`) so it can sit under the
/// import group the way the prototype orders the page.
struct ResetSettingsSection: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @State private var showingResetConfirm = false
    @State private var isBusy = false
    @State private var didReset = false

    var body: some View {
        SettingsSection(note: didReset ? "Everything was reset." : nil) {
            SettingsLinkRow(
                label: "Reset everything", sub: "Erase all data and settings on this device",
                labelTint: DGColor.danger, isBusy: isBusy
            ) {
                showingResetConfirm = true
            }
        }
        .sheet(isPresented: $showingResetConfirm) {
            ResetAllDataSheet(onConfirm: performReset)
        }
    }

    /// `wipeAllData` deletes every row one at a time and reseeds the library, routines and
    /// equipment before returning — seconds of main-actor work. The yield lets the confirm sheet
    /// finish dismissing and the row's spinner paint before that starts, so the reset no longer
    /// looks hung.
    private func performReset() {
        isBusy = true
        Task {
            defer { isBusy = false }
            await Task.yield()
            store.wipeAllData(preferences: preferences)
            didReset = true
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            SettingsPage(title: "Data & backup") { ResetSettingsSection() }
        }
        .environment(store)
        .environment(Preferences())
    }
}
