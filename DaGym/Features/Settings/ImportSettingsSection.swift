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
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 56)
        }
        .buttonStyle(.dgRow)
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
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DGColor.ink4)
                }
            }
            .padding(.horizontal, DGSpace.s5)
            .frame(minHeight: 56)
        }
        .buttonStyle(.dgRow)
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
        pendingImport = PendingCSVImport(preview: preview, csv: csv)
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
        guard let csv = pending.csv,
              let preview = WorkoutImportService.preview(
                  csv: csv, store: store, assumedWeightUnit: unit
              ) else { return }
        pendingImport = pending.reparsed(preview: preview)
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
        pendingImport = PendingCSVImport(
            preview: WorkoutImportService.preview(result: result, store: store), csv: nil
        )
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
                    .buttonStyle(.dgControl)
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

/// Source badge, counts, unmatched exercises and problems for one parsed CSV, before the user
/// confirms the import.
private struct ImportCSVPreviewSheet: View {
    var preview: ImportPreview
    var onConfirm: () -> Void
    var onCancel: () -> Void
    /// Called when the user picks a weight unit for a file that named none; nil hides the picker.
    var onPickUnit: ((WeightUnit) -> Void)?

    /// The picker's own selection. Routing the choice through `@State` + `onChange` rather than a
    /// `Binding(get:set:)` over `onPickUnit` keeps a non-`Sendable` closure out of `Binding`'s
    /// `@Sendable` setter — which Swift 6 rejects, and which the compiler crashes on if you make
    /// the closure type `@MainActor @Sendable` to satisfy it.
    @State private var pickedUnit = WeightUnit.kg

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
                    if preview.weightUnitAssumed, let onPickUnit {
                        unitPicker(onPickUnit)
                    }
                    if !preview.matchedExercises.isEmpty {
                        namesCard(
                            title: "\(preview.matchedExercises.count) matched exercise"
                                + (preview.matchedExercises.count == 1 ? "" : "s"),
                            names: preview.matchedExercises.map { "\($0.sourceName) → \($0.libraryName)" }
                        )
                    }
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
        VStack(spacing: DGSpace.s2) {
            DGAdaptiveStack(spacing: 0, threshold: .accessibility3) {
                StatTile(value: "\(preview.newWorkoutCount)", label: "Workouts")
                StatTile(value: "\(preview.setsCount)", label: "Sets")
            }
            .dgCard(padding: 0)
            if preview.alreadyImportedCount > 0 {
                Text("\(preview.alreadyImportedCount) already in your history — they'll be skipped.")
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Shown only when the file's weight column named no unit. Assuming kg silently turns an
    /// American lifter's 225 lb bench into a 225 kg one, so the guess is made visible and
    /// changeable before anything is written.
    private func unitPicker(_ onPick: @escaping (WeightUnit) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Weight unit").dgLabel()
            Text("This file doesn't say what unit its weights are in. Reading them as:")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink3)
            Picker("Weight unit", selection: $pickedUnit) {
                Text("Kilograms").tag(WeightUnit.kg)
                Text("Pounds").tag(WeightUnit.lb)
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DGSpace.s4)
        .dgCard(padding: 0)
        .onAppear { pickedUnit = preview.weightUnit }
        // Only a real change re-parses; the `onAppear` seed above must not kick one off.
        .onChange(of: pickedUnit) { _, unit in
            if unit != preview.weightUnit { onPick(unit) }
        }
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
                .buttonStyle(.dgControl)
                .font(DGFont.condensedLabel(15))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink3)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
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
