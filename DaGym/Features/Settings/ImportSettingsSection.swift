import GymCore
import SwiftUI
import UniformTypeIdentifiers

/// The Settings "IMPORT HISTORY" section: pick a Strong/Hevy/FitNotes CSV export via
/// `.fileImporter`, preview what it would add, then confirm to merge (plan.md §6.8: "Import
/// history from other apps... show a preview + problems before confirming").
struct ImportSettingsSection: View {
    @Environment(WorkoutStore.self) private var store

    @State private var isBusy = false
    @State private var showingImporter = false
    @State private var pendingImport: PendingCSVImport?
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showingHevyKeySheet = false
    @State private var hevyAPIKey = KeychainStore.string(account: HevyAPIClient.keychainAccount) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Import History").dgLabel()
            VStack(spacing: 0) {
                importRow
                Divider().padding(.leading, 52)
                hevyRow
            }
            .dgCard(padding: 0)
            footnote
        }
        .fileImporter(
            isPresented: $showingImporter, allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            handleImportPick(result)
        }
        .sheet(item: $pendingImport) { pending in
            ImportCSVPreviewSheet(
                preview: pending.preview, onConfirm: { confirmImport(pending.preview) },
                onCancel: { pendingImport = nil }
            )
        }
        .sheet(isPresented: $showingHevyKeySheet) {
            HevyAPIKeySheet(apiKey: hevyAPIKey, onSave: saveHevyKey, onRemove: removeHevyKey)
        }
        .alert(
            "Couldn't Complete That", isPresented: errorBinding,
            actions: {}, message: { Text(errorMessage ?? "") }
        )
    }

    private var importRow: some View {
        Button { showingImporter = true } label: {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.coral)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from Strong, Hevy or FitNotes")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                    Text("Bring in workout history from a CSV export")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink4)
                }
                Spacer()
                if isBusy {
                    ProgressView().tint(DGColor.ink3)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private var hevyRow: some View {
        Button(action: hevyRowTapped) {
            HStack(spacing: DGSpace.s3) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DGColor.coral)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hevyAPIKey.isEmpty ? "Import from Hevy (API)" : "Import from Hevy")
                        .font(DGFont.body)
                        .foregroundStyle(DGColor.ink1)
                    Text(
                        hevyAPIKey.isEmpty
                            ? "Connect with your Hevy Pro API key"
                            : "Fetch your full workout history"
                    )
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                }
                Spacer()
                if isBusy {
                    ProgressView().tint(DGColor.ink3)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    @ViewBuilder
    private var footnote: some View {
        if let confirmationMessage {
            Text(confirmationMessage).font(DGFont.footnote).foregroundStyle(DGColor.success)
        } else {
            Text("Unmatched exercises are added as custom exercises. Nothing is dropped.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
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
        guard let preview = WorkoutImportService.preview(csv: csv, store: store) else {
            errorMessage = "That doesn't look like a Strong, Hevy or FitNotes export."
            return
        }
        pendingImport = PendingCSVImport(preview: preview)
    }

    private func readCSV(url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }.value
    }

    private func confirmImport(_ preview: ImportPreview) {
        let report = WorkoutImportService.apply(preview: preview, store: store)
        pendingImport = nil
        confirmationMessage = report.summary
    }

    // MARK: - Hevy API import

    private func hevyRowTapped() {
        if hevyAPIKey.isEmpty {
            showingHevyKeySheet = true
        } else {
            Task { await loadHevyImport() }
        }
    }

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
        pendingImport = PendingCSVImport(preview: WorkoutImportService.preview(result: result, store: store))
    }
}

/// A single API-key text field, presented the first time "Import from Hevy" is tapped and
/// reachable again from the same row afterward to remove the key.
private struct HevyAPIKeySheet: View {
    var apiKey: String
    var onSave: (String) -> Void
    var onRemove: () -> Void

    @State private var draft = ""

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Hevy API Key")
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Text(
                    "From hevy.app → Settings → API (Hevy Pro). Stored in the Keychain — it's only "
                        + "ever sent to Hevy's own API."
                )
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("API key", text: $draft)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(DGSpace.s4)
                .dgCard(padding: 0)
            DGPrimaryButton(title: "Connect", action: save)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !apiKey.isEmpty {
                Button("Remove Key", role: .destructive, action: onRemove)
                    .buttonStyle(.plain)
                    .dgLabel(DGColor.danger)
            }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
        .task { draft = apiKey }
    }

    private func save() {
        onSave(draft.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Wraps `ImportPreview` for `.sheet(item:)`, which needs `Identifiable`.
private struct PendingCSVImport: Identifiable {
    let id = UUID()
    var preview: ImportPreview
}

/// Source badge, counts, unmatched exercises and problems for one parsed CSV, before the user
/// confirms the import.
private struct ImportCSVPreviewSheet: View {
    var preview: ImportPreview
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            header
            // The unmatched-name and problem lists are unbounded (a Strong export can carry
            // dozens), so they scroll and the Cancel/Import row stays reachable underneath.
            ScrollView {
                VStack(spacing: DGSpace.s5) {
                    countsCard
                    if !preview.unmatchedExerciseNames.isEmpty {
                        namesCard(
                            title: "\(preview.unmatchedExerciseNames.count) new exercise"
                                + (preview.unmatchedExerciseNames.count == 1 ? "" : "s"),
                            names: preview.unmatchedExerciseNames
                        )
                    }
                    if !preview.problems.isEmpty {
                        namesCard(
                            title: "\(preview.problems.count) problem"
                                + (preview.problems.count == 1 ? "" : "s"),
                            names: preview.problems.map { "Line \($0.line): \($0.message)" }
                        )
                    }
                }
            }
            actions
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents(hasExtras ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.hidden)
    }

    private var hasExtras: Bool {
        !preview.unmatchedExerciseNames.isEmpty || !preview.problems.isEmpty
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Import from \(preview.source.displayName)")
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text("Nothing is imported until you confirm")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countsCard: some View {
        HStack(spacing: 0) {
            StatTile(value: "\(preview.workouts.count)", label: "Workouts")
            StatTile(value: "\(preview.setsCount)", label: "Sets")
        }
        .dgCard(padding: 0)
    }

    private func namesCard(title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(title).dgLabel()
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                ForEach(names, id: \.self) { name in
                    Text(name).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DGSpace.s4)
            .dgCard(padding: 0)
        }
    }

    private var actions: some View {
        HStack(spacing: DGSpace.s3) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .font(DGFont.condensedLabel(15))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink3)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .dgGlass(.regular, radius: DGRadius.lg)
            DGPrimaryButton(title: "Import", action: onConfirm)
        }
    }
}

#Preview {
    if let store = PreviewStore.make() {
        ScrollView {
            ImportSettingsSection()
                .padding(DGSpace.s4)
        }
        .environment(store)
        .background(AmbientWash())
    }
}
