import GymCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Data & backup › "Import from another app": one row per source. Strong, Hevy and
/// FitNotes CSV exports all go through the same `.fileImporter` (the format is detected from
/// the header), Hevy can also fetch over its API, and Apple Health hands off to
/// `HealthImportRow`. Every path previews what it would add, then confirms to merge (plan.md
/// §6.8: "Import history from other apps... show a preview + problems before confirming").
struct ImportSettingsSection: View {
    @Environment(WorkoutStore.self) private var store

    @State private var isBusy = false
    @State private var showingImporter = false
    @State private var pendingImport: PendingCSVImport?
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showingHevyKeySheet = false
    @State private var showingHevyChoice = false
    /// The in-flight unit re-parse; a new pick cancels it so a slow LB parse can't land after a
    /// faster KG one and import every weight 2.2× off.
    @State private var reparseTask: Task<Void, Never>?
    /// Read in `.task`, not here: a `@State` initial value is evaluated on every `SettingsView`
    /// render, which made every stepper tap up there a Keychain round-trip.
    @State private var hevyAPIKey = ""
    /// Non-nil while `ImportActor` is writing: what the progress line shows.
    @State private var importProgress: ImportProgress?
    /// The import in flight, so Cancel can stop it between batches.
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            SettingsSection(title: "Import from another app") {
                SettingsLinkRow(label: "Strong · CSV", isBusy: isBusy) { showingImporter = true }
                SettingsDivider()
                SettingsLinkRow(label: "Hevy · CSV or API key", sub: hevySub, isBusy: isBusy) {
                    showingHevyChoice = true
                }
                SettingsDivider()
                SettingsLinkRow(label: "FitNotes · CSV", isBusy: isBusy) { showingImporter = true }
                SettingsDivider()
                HealthImportRow()
            }
            footnote
        }
        .fileImporter(
            isPresented: $showingImporter, allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            handleImportPick(result)
        }
        .confirmationDialog("Import from Hevy", isPresented: $showingHevyChoice, titleVisibility: .visible) {
            Button("Choose a CSV export") { showingImporter = true }
            if hevyAPIKey.isEmpty {
                Button("Connect with a Hevy API key") { showingHevyKeySheet = true }
            } else {
                Button("Fetch from Hevy") { Task { await loadHevyImport() } }
                Button("Change or remove API key") { showingHevyKeySheet = true }
            }
        }
        .sheet(item: $pendingImport) { pending in
            ImportCSVPreviewSheet(
                preview: pending.preview, onConfirm: { confirmImport(pending.preview) },
                onCancel: { pendingImport = nil },
                onPickUnit: unitPicker(for: pending)
            )
        }
        .sheet(isPresented: $showingHevyKeySheet) {
            HevyAPIKeySheet(apiKey: hevyAPIKey, onSave: saveHevyKey, onRemove: removeHevyKey)
        }
        .alert(
            "Couldn't Complete That", isPresented: errorBinding,
            actions: {}, message: { Text(errorMessage ?? "") }
        )
        .task { hevyAPIKey = KeychainStore.string(account: HevyAPIClient.keychainAccount) ?? "" }
    }

    private var hevySub: String? {
        hevyAPIKey.isEmpty ? nil : "API key saved"
    }

    @ViewBuilder
    private var footnote: some View {
        if let importProgress {
            ImportProgressRow(title: "Importing", progress: importProgress) { importTask?.cancel() }
        } else if let confirmationMessage {
            SettingsNote(text: confirmationMessage, tint: DGColor.success)
        } else {
            SettingsNote(text: "Unmatched exercises are added as custom exercises. Nothing is dropped.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func handleImportPick(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task { await loadImport(url: url) }
        case .failure(let error):
            errorMessage = "Couldn't open that file: \(error.localizedDescription)"
        }
    }

    private func loadImport(url: URL) async {
        isBusy = true
        defer { isBusy = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let csv = await readCSV(url: url) else {
            errorMessage = "Couldn't read that file."
            return
        }
        guard let preview = await parsePreview(csv: csv, assumedWeightUnit: nil) else {
            errorMessage = "That doesn't look like a Strong, Hevy or FitNotes export."
            return
        }
        pendingImport = PendingCSVImport(preview: preview, csv: csv)
    }

    /// The parse (`WorkoutImport.parse`, pure over the text) runs off the main thread; only the
    /// name-matching against the library, which needs the store's main-actor context, runs here.
    /// A multi-thousand-row Strong export used to parse on main and beach-ball Settings.
    private func parsePreview(csv: String, assumedWeightUnit: WeightUnit?) async -> ImportPreview? {
        let result = await Task.detached(priority: .userInitiated) {
            WorkoutImport.parse(csv: csv, assumedWeightUnit: assumedWeightUnit)
        }.value
        guard let result else { return nil }
        return WorkoutImportService.preview(
            result: result, store: store, assumedWeightUnit: assumedWeightUnit
        )
    }

    /// The picker's action, or nil for a source with no re-parsable text (the Hevy API path,
    /// whose weights are already unambiguously kg).
    private func unitPicker(for pending: PendingCSVImport) -> ((WeightUnit) -> Void)? {
        guard pending.csv != nil else { return nil }
        return { unit in reparse(pending, unit: unit) }
    }

    /// Re-runs the parse with the unit the user picked, for a file whose weight column named none.
    /// Re-parsing (rather than scaling the already-parsed numbers) keeps one code path honest
    /// about per-row unit columns and rounding.
    private func reparse(_ pending: PendingCSVImport, unit: WeightUnit) {
        guard let csv = pending.csv else { return }
        reparseTask?.cancel()
        reparseTask = Task {
            guard let preview = await parsePreview(csv: csv, assumedWeightUnit: unit),
                  !Task.isCancelled else { return }
            pendingImport = pending.reparsed(preview: preview)
        }
    }

    private func readCSV(url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }.value
    }

    /// The sheet comes down first; the rows are written by `ImportActor` off the main actor, with
    /// each landed batch reported through the relay to the progress line. A cancel keeps the
    /// workouts that had landed (re-importing the file skips them) and says so.
    private func confirmImport(_ preview: ImportPreview) {
        pendingImport = nil
        isBusy = true
        importProgress = ImportProgress(done: 0, total: preview.workouts.count)
        let relay = ImportProgressRelay()
        let observer = relay.observe { importProgress = $0 }
        importTask = Task {
            defer {
                relay.finish()
                observer.cancel()
                importProgress = nil
                importTask = nil
                isBusy = false
            }
            do {
                let report = try await WorkoutImportService.apply(
                    preview: preview, store: store, progress: relay.handler
                )
                confirmationMessage = report.summary
            } catch is CancellationError {
                confirmationMessage = "Import cancelled — what had already been imported was kept"
            } catch {
                errorMessage = "Couldn't import that file: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Hevy API import

    private func saveHevyKey(_ key: String) {
        hevyAPIKey = key
        KeychainStore.set(key, account: HevyAPIClient.keychainAccount)
        showingHevyKeySheet = false
        Task { await loadHevyImport() }
    }

    private func removeHevyKey() {
        hevyAPIKey = ""
        KeychainStore.remove(account: HevyAPIClient.keychainAccount)
        showingHevyKeySheet = false
    }

    private func loadHevyImport() async {
        guard !hevyAPIKey.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        let (workouts, problems) = await HevyAPIClient.fetchAllWorkouts(apiKey: hevyAPIKey)
        guard !workouts.isEmpty || !problems.isEmpty else {
            errorMessage = "No workouts found for that Hevy account."
            return
        }
        let result = ImportResult(source: .hevy, workouts: workouts, problems: problems)
        pendingImport = PendingCSVImport(
            preview: WorkoutImportService.preview(result: result, store: store), csv: nil
        )
    }
}

/// Wraps `ImportPreview` for `.sheet(item:)`, which needs `Identifiable`.
/// Not private: `FeatureImportSheetTests` checks `reparsed(preview:)` keeps the sheet's identity.
struct PendingCSVImport: Identifiable {
    /// Explicit so a re-parse can keep it: `.sheet(item:)` keys the sheet on `id`, and a fresh
    /// UUID on every unit pick dismissed and re-presented the sheet mid-tap.
    var id = UUID()
    var preview: ImportPreview
    /// The file's text, kept so the preview can be re-parsed in a different weight unit. Nil for
    /// the Hevy API path, whose weights are already unambiguously kg.
    var csv: String?

    /// The same pending import (same `id`, same file) with the preview from a re-parse, so the
    /// open sheet updates in place instead of animating down and back up.
    func reparsed(preview: ImportPreview) -> PendingCSVImport {
        var copy = self
        copy.preview = preview
        return copy
    }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            SettingsPage(title: "Data & backup") { ImportSettingsSection() }
        }
        .environment(store)
        .environment(Preferences())
    }
}
