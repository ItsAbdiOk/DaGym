import SwiftUI

/// The "N workouts found in Health" row — the visible, explicit path for strength sessions
/// logged in another app (or the Watch) to land in History. Never imports silently: the only
/// call to `HealthInsightsService.importPendingExternalWorkouts()` is this row's own button
/// tap. Lives on both the Apple Health page and the Data & backup page's "Import from another
/// app" group, with its own state so either copy works alone.
struct HealthImportRow: View {
    @Environment(Preferences.self) private var preferences
    @Environment(HealthInsightsService.self) private var healthInsights
    @State private var pendingImportCount = 0
    @State private var isImporting = false
    @State private var importedTitles: [String] = []
    @State private var showingImportResult = false

    var body: some View {
        SettingsLinkRow(label: "Apple Health", sub: sub, isBusy: isImporting, action: importWorkouts)
            .disabled(!canImport)
            .accessibilityLabel(rowLabel)
            .accessibilityHint(
                canImport ? "Imports these workouts from Apple Health into History." : ""
            )
            .task { await refreshPendingImportCount() }
            // Turning "Import workouts from other apps" on higher up the Apple Health page should
            // make the count appear at once, not after the page is reopened.
            .onChange(of: preferences.healthImportWorkouts) { _, _ in
                Task { await refreshPendingImportCount() }
            }
            .alert("Apple Health Import", isPresented: $showingImportResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importResultMessage)
            }
    }

    private var canImport: Bool { preferences.healthImportWorkouts && pendingImportCount > 0 }

    private var sub: String {
        guard preferences.healthImportWorkouts else {
            return "Turn on “Import workouts from other apps” under Apple Health"
        }
        let noun = pendingImportCount == 1 ? "workout" : "workouts"
        return isImporting ? "Importing…" : "\(pendingImportCount) \(noun) found"
    }

    private var rowLabel: String { "Apple Health, \(sub)" }

    private var importResultMessage: String {
        guard !importedTitles.isEmpty else { return "No new workouts to import." }
        let count = importedTitles.count
        let noun = count == 1 ? "workout" : "workouts"
        return "Imported \(count) \(noun): \(importedTitles.joined(separator: ", "))"
    }

    private func refreshPendingImportCount() async {
        pendingImportCount = await healthInsights.pendingExternalWorkouts().count
    }

    private func importWorkouts() {
        isImporting = true
        Task {
            let imported = await healthInsights.importPendingExternalWorkouts()
            importedTitles = imported.map(\.title)
            await refreshPendingImportCount()
            isImporting = false
            showingImportResult = true
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        let preferences = Preferences()
        return AnyView(
            NavigationStack {
                SettingsPage(title: "Apple Health") {
                    SettingsSection { HealthImportRow() }
                }
            }
            .environment(preferences)
            .environment(store)
            .environment(HealthInsightsService(
                healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
            ))
        )
    }
    return AnyView(EmptyView())
}
