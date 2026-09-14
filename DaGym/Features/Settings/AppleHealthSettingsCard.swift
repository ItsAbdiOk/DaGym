import SwiftUI

/// The "Apple Health" card in `SettingsView`: the Apple Health and Bodyweight rows that were
/// already there, plus the "N workouts found in Health" import row — the visible, explicit path
/// for strength sessions logged in another app (or the Watch) to land in History. Never imports
/// silently: the only call to `HealthInsightsService.importPendingExternalWorkouts()` is this
/// row's own button tap. Kept as its own view (with its own state) rather than a `SettingsView`
/// extension so `SettingsView`'s body stays under the type-body-length lint limit.
struct AppleHealthSettingsCard: View {
    @Environment(Preferences.self) private var preferences
    @Environment(HealthInsightsService.self) private var healthInsights
    @State private var showingHealthSettings = false
    @State private var showingBodyweightSheet = false
    @State private var pendingImportCount = 0
    @State private var isImporting = false
    @State private var importedTitles: [String] = []
    @State private var showingImportResult = false

    var body: some View {
        SettingsSection(title: "Apple Health") {
            Button { showingHealthSettings = true } label: {
                SettingsRow(label: "Apple Health") { chevron }
            }
            .buttonStyle(.dgRow)
            SettingsDivider()
            Button { showingBodyweightSheet = true } label: {
                SettingsRow(label: "Bodyweight") { chevron }
            }
            .buttonStyle(.dgRow)
            if preferences.healthImportWorkouts, pendingImportCount > 0 {
                SettingsDivider()
                importRow
            }
        }
        .sheet(isPresented: $showingHealthSettings, onDismiss: refresh) { HealthSettingsView() }
        .sheet(isPresented: $showingBodyweightSheet) { BodyweightSheet() }
        .task { await refreshPendingImportCount() }
        .alert("Apple Health Import", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResultMessage)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DGColor.ink4)
    }

    private var importRow: some View {
        Button(action: importWorkouts) {
            SettingsRow(label: importRowLabel) {
                if isImporting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DGColor.coralText)
                }
            }
        }
        .buttonStyle(.dgRow)
        .disabled(isImporting)
        .accessibilityLabel(importRowLabel)
        .accessibilityHint("Imports these workouts from Apple Health into History.")
    }

    private var importRowLabel: String {
        let noun = pendingImportCount == 1 ? "workout" : "workouts"
        return isImporting ? "Importing…" : "\(pendingImportCount) \(noun) found in Health"
    }

    private var importResultMessage: String {
        guard !importedTitles.isEmpty else { return "No new workouts to import." }
        let count = importedTitles.count
        let noun = count == 1 ? "workout" : "workouts"
        return "Imported \(count) \(noun): \(importedTitles.joined(separator: ", "))"
    }

    /// Turning "Import workouts from other apps" on inside the Apple Health sheet should make
    /// this row appear the moment the user comes back, not after a manual re-open.
    private func refresh() {
        Task { await refreshPendingImportCount() }
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
            AppleHealthSettingsCard()
                .padding()
                .environment(preferences)
                .environment(store)
                .environment(HealthInsightsService(
                    healthStore: HealthKitStore(), workoutStore: store, preferences: preferences
                ))
        )
    }
    return AnyView(EmptyView())
}
