import GymCore
import os
import SwiftData
import SwiftUI

/// The Settings "DATA" section: export a full JSON backup via `.fileExporter`,
/// or import one back in via `.fileImporter` — preview counts, then confirm
/// to merge (plan.md §6.3). The file read, JSON decode/encode and document build run
/// off the main thread; `BackupService` itself is main-actor bound (it walks the store's
/// `ModelContext`), so the model walk on export and the row writes on import still run
/// here — after a yield, so the row's spinner is on screen while they do.
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
    @State private var showingResetConfirm = false
    @State private var exportWarning: String?
    /// The finished import's report, so its problems stay readable after the sheet is dismissed.
    @State private var completedReport: ImportReport?

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            Text("Data").dgLabel()
            VStack(spacing: 0) {
                exportRow
                Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                importRow
                Divider().overlay(DGColor.hairline).padding(.leading, DGSpace.s5)
                resetRow
            }
            .dgCard(padding: 0)
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
        .sheet(isPresented: $showingResetConfirm) {
            ResetAllDataSheet(onConfirm: performReset)
        }
    }

    private var resetRow: some View {
        Button { showingResetConfirm = true } label: {
            DataRow(
                title: "Reset everything…", subtitle: "Erase all data and settings on this device",
                symbol: "trash", isBusy: isBusy, tint: DGColor.danger, titleTint: DGColor.danger
            )
        }
        .buttonStyle(.dgRow)
        .disabled(isBusy)
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
            completedReport = nil
            exportWarning = nil
            confirmationMessage = "Everything was reset"
        }
    }

    private var exportRow: some View {
        Button { Task { await prepareExport() } } label: {
            DataRow(
                title: "Export backup…", subtitle: "Save everything as a JSON file",
                symbol: "square.and.arrow.up", isBusy: isBusy
            )
        }
        .buttonStyle(.dgRow)
        .disabled(isBusy)
    }

    private var importRow: some View {
        Button { showingImporter = true } label: {
            DataRow(
                title: "Import backup…", subtitle: "Merge a previously exported file",
                symbol: "square.and.arrow.down", isBusy: isBusy
            )
        }
        .buttonStyle(.dgRow)
        .disabled(isBusy)
    }

    @ViewBuilder
    private var footnote: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            if let confirmationMessage {
                Text(confirmationMessage)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.success)
            } else {
                Text(
                    "Backups include routines, workouts, custom exercises, equipment profiles, "
                        + "progress photos and your settings."
                )
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
            }
            if let exportWarning {
                Text(exportWarning).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
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
                    Text(problem).font(DGFont.footnote).foregroundStyle(DGColor.danger)
                }
                if problems.count > 8 {
                    Text("…and \(problems.count - 8) more.")
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.danger)
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
    /// The sheet comes down first and the row spins while `BackupService.import` writes every
    /// row on the main actor; the yield is what gets that spinner on screen before it starts.
    private func confirmImport(_ document: BackupDocument) {
        pendingImport = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            await Task.yield()
            let interval = Self.signposter.beginInterval("backup.import")
            let report = await BackupService.import(
                document: document, store: store, preferences: preferences
            )
            Self.signposter.endInterval("backup.import", interval)
            completedReport = report
            confirmationMessage = report.summary
        }
    }
}

/// Row chrome shared by the export/import buttons: icon, title, subtitle,
/// trailing chevron (or a spinner while busy).
private struct DataRow: View {
    var title: String
    var subtitle: String
    var symbol: String
    var isBusy: Bool
    var tint: Color = DGColor.coral
    var titleTint: Color = DGColor.ink1

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DGFont.body).foregroundStyle(titleTint)
                Text(subtitle).font(DGFont.footnote).foregroundStyle(DGColor.ink4)
            }
            Spacer()
            if isBusy {
                ProgressView().tint(DGColor.ink3).accessibilityLabel("In progress")
            } else {
                Image(systemName: "chevron.right").accessibilityHidden(true)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
        }
        .padding(.horizontal, DGSpace.s5)
        .frame(minHeight: 56)
    }
}

extension BackupDocument: @retroactive Identifiable {
    public var id: Date { exportedAt }
}

#Preview {
    if let store = PreviewStore.make() {
        ScrollView {
            DataSettingsSection()
                .padding(DGSpace.s4)
        }
        .environment(store)
        .environment(Preferences())
        .background(AmbientWash())
    }
}
