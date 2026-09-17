import GymCore
import os
import SwiftData
import SwiftUI

/// Settings › Data & backup, first group: export a full JSON backup via `.fileExporter`,
/// or import one back in via `.fileImporter` — preview counts, then confirm
/// to merge (plan.md §6.3). The reset row is `ResetSettingsSection`, at the foot of the page.
/// The file read, JSON decode/encode and document build run off the main thread, and so do the
/// row writes on import (`ImportActor`, batched, with the progress line and Cancel below the
/// row); only the export's model walk is main-actor bound (it walks the store's `ModelContext`)
/// and runs here after a yield so the spinner paints.
struct DataSettingsSection: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    /// `backup.export` / `backup.import` intervals for Instruments; the preview that precedes
    /// an import is `backup.preview`.
    private static let signposter = OSSignposter(subsystem: "dev.abdirahmanmohamed.dagym", category: "perf")
    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @State private var isBusy = false
    @State private var exportDocument: BackupFileDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImport: BackupDocument?
    @State private var pendingReport: ImportReport?
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var exportWarning: String?
    /// The finished import's report, so its problems stay readable after the sheet is dismissed.
    @State private var completedReport: ImportReport?
    /// Non-nil while `ImportActor` is restoring: what the progress line shows.
    @State private var importProgress: ImportProgress?
    /// The restore in flight, so Cancel can stop it between batches.
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            SettingsSection {
                SettingsLinkRow(
                    label: "Export backup", sub: "Save everything as a JSON file", isBusy: isBusy
                ) {
                    Task { await prepareExport() }
                }
                SettingsDivider()
                SettingsLinkRow(
                    label: "Import backup", sub: "Merge a previously exported file", isBusy: isBusy
                ) {
                    showingImporter = true
                }
            }
            footnote
        }
        .fileExporter(
            isPresented: $showingExporter, document: exportDocument, contentType: .json,
            defaultFilename: Self.exportFilename()
        ) { result in
            if case .failure(let error) = result {
                errorMessage = "Couldn't save the backup: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            handleImportPick(result)
        }
        .sheet(item: $pendingImport) { document in
            ImportPreviewSheet(
                document: document, report: pendingReport ?? ImportReport(),
                onConfirm: { confirmImport(document) }, onCancel: { pendingImport = nil }
            )
        }
        .alert(
            "Couldn't Complete That", isPresented: errorBinding,
            actions: {}, message: { Text(errorMessage ?? "") }
        )
    }

    @ViewBuilder
    private var footnote: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            if let importProgress {
                ImportProgressRow(title: "Importing", progress: importProgress) { importTask?.cancel() }
            } else if let confirmationMessage {
                SettingsNote(text: confirmationMessage, tint: DGColor.success)
            } else {
                SettingsNote(
                    text: "Backups include routines, workouts, custom exercises, equipment profiles, "
                        + "progress photos and your settings."
                )
            }
            if let exportWarning {
                SettingsNote(text: exportWarning)
            }
            problemsFootnote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every problem the finished import reported, listed — not summarised away. A user who is
    /// told "12 workouts" while 300 rows were skipped has no way to know anything went wrong.
    @ViewBuilder
    private var problemsFootnote: some View {
        if let problems = completedReport?.problems, !problems.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(problems.prefix(8), id: \.self) { problem in
                    SettingsNote(text: problem, tint: DGColor.danger)
                }
                if problems.count > 8 {
                    SettingsNote(text: "…and \(problems.count - 8) more.", tint: DGColor.danger)
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: - Export

    private func prepareExport() async {
        isBusy = true
        defer { isBusy = false }
        // Let the spinner paint before the main-actor walk over every model.
        await Task.yield()
        let interval = Self.signposter.beginInterval("backup.export")
        defer { Self.signposter.endInterval("backup.export", interval) }
        let result = BackupService.exportResult(
            context: store.context, photoContext: store.photoContext,
            healthContext: store.healthContext, preferences: preferences
        )
        let document = result.document
        do {
            exportDocument = try await Task.detached(priority: .userInitiated) {
                try BackupFileDocument(data: BackupCodec.encode(document))
            }.value
            showingExporter = true
            // Anything the export couldn't carry faithfully (history on a deleted exercise, a
            // photo too large for one file) is said out loud rather than left for the user to
            // discover on a restore.
            exportWarning = result.problems.isEmpty ? nil : result.problems.joined(separator: " ")
        } catch {
            errorMessage = "Couldn't create the backup file."
        }
    }

    /// Not private: `SettingsSectionsTests` pins the date-stamped name.
    static func exportFilename(on date: Date = Date()) -> String {
        "DaGym-backup-\(filenameFormatter.string(from: date))"
    }

    // MARK: - Import

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
        let interval = Self.signposter.beginInterval("backup.preview")
        defer { Self.signposter.endInterval("backup.preview", interval) }
        do {
            // The scoped access above is held until this function returns, which is after the
            // detached read finishes.
            let document = try await Task.detached(priority: .userInitiated) {
                try BackupCodec.decode(Data(contentsOf: url))
            }.value
            pendingReport = BackupService.preview(document: document, context: store.context)
            pendingImport = document
        } catch let error as BackupCodec.CodecError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "That file isn't a valid DaGym backup."
        }
    }

    private static func message(for error: BackupCodec.CodecError) -> String {
        switch error {
        case .unsupportedFormatVersion:
            return "That backup was made by a newer version of DaGym. Update the app and try again."
        case .decodingFailed:
            return "That file isn't a valid DaGym backup."
        }
    }

    /// The report is what the user gets told. It used to be discarded and replaced with a flat
    /// "Imported", so a restore that dropped hundreds of rows (every workout on a seeded exercise,
    /// after a reset) read exactly like a clean one.
    ///
    /// The sheet comes down first; the rows are written by `ImportActor` off the main actor, with
    /// each landed batch reported through the relay to the progress line. A cancel keeps the
    /// batches that had landed (re-importing the file skips them) and says so.
    private func confirmImport(_ document: BackupDocument) {
        pendingImport = nil
        isBusy = true
        importProgress = ImportProgress(done: 0, total: 0)
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
            let interval = Self.signposter.beginInterval("backup.import")
            defer { Self.signposter.endInterval("backup.import", interval) }
            do {
                let report = try await BackupService.import(
                    document: document, store: store, preferences: preferences, progress: relay.handler
                )
                completedReport = report
                confirmationMessage = report.summary
            } catch is CancellationError {
                completedReport = nil
                confirmationMessage = "Import cancelled — what had already been imported was kept"
            } catch {
                errorMessage = "Couldn't import the backup: \(error.localizedDescription)"
            }
        }
    }
}

extension BackupDocument: @retroactive Identifiable {
    public var id: Date { exportedAt }
}

#Preview {
    if let store = PreviewStore.make() {
        NavigationStack {
            SettingsPage(title: "Data & backup") { DataSettingsSection() }
        }
        .environment(store)
        .environment(Preferences())
    }
}
