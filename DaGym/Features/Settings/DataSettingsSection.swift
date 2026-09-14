import GymCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The Settings "DATA" section: export a full JSON backup via `.fileExporter`,
/// or import one back in via `.fileImporter` — preview counts, then confirm
/// to merge (plan.md §6.3). Decoding/encoding run off the main thread so a
/// large file never hitches the UI.
struct DataSettingsSection: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(Preferences.self) private var preferences

    @State private var isBusy = false
    @State private var exportDocument: BackupFileDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImport: BackupDocument?
    @State private var pendingReport: ImportReport?
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showingResetConfirm = false

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

    private func performReset() {
        store.wipeAllData(preferences: preferences)
        confirmationMessage = "Everything was reset"
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
        if let confirmationMessage {
            Text(confirmationMessage)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.success)
        } else {
            Text("Backups include routines, workouts, custom exercises and equipment profiles.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // MARK: - Export

    private func prepareExport() async {
        isBusy = true
        defer { isBusy = false }
        let document = BackupService.export(context: store.context)
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try BackupCodec.encode(document)
            }.value
            exportDocument = BackupFileDocument(data: data)
            showingExporter = true
        } catch {
            errorMessage = "Couldn't create the backup file."
        }
    }

    private static func exportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "DaGym-backup-\(formatter.string(from: Date()))"
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
        do {
            let data = try Data(contentsOf: url)
            let document = try await Task.detached(priority: .userInitiated) {
                try BackupCodec.decode(data)
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

    private func confirmImport(_ document: BackupDocument) {
        BackupService.import(document: document, context: store.context, mode: .merge)
        pendingImport = nil
        confirmationMessage = "Imported"
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
}

/// Wraps raw JSON `Data` so `.fileExporter` can save it without an
/// intermediate temp file.
struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension BackupDocument: @retroactive Identifiable {
    public var id: Date { exportedAt }
}

/// Typed-confirm gate in front of `WorkoutStore.wipeAllData(preferences:)` — the delete button
/// stays disabled until the user types "DELETE" exactly, so a destructive row can't fire from a
/// stray tap or a misread confirmation alert.
private struct ResetAllDataSheet: View {
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private static let confirmationWord = "DELETE"

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            HStack {
                Text("Reset Everything").font(DGFont.title2).foregroundStyle(DGColor.ink1)
                Spacer()
                DGIconButton(symbol: "xmark", accessibilityLabel: "Close") { dismiss() }
            }
            Text(
                "This permanently deletes every routine, workout, exercise, progress photo and "
                    + "setting on this device. It can't be undone."
            )
            .font(DGFont.body)
            .foregroundStyle(DGColor.ink3)
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                Text("Type DELETE to confirm").font(DGFont.footnote).foregroundStyle(DGColor.ink4)
                TextField(Self.confirmationWord, text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(DGFont.body)
                    .padding(DGSpace.s3)
                    .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            DGPrimaryButton(title: "Delete Everything", symbol: "trash", fill: DGColor.danger, height: 52) {
                onConfirm()
                dismiss()
            }
            .disabled(typed != Self.confirmationWord)
            .opacity(typed == Self.confirmationWord ? 1 : 0.4)
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, DGSpace.s6)
        .padding(.bottom, DGSpace.s8)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
    }
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
