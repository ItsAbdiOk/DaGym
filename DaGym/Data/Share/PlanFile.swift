import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// `.gymplan` — a shareable routine/program file (plan.md §6.8). Declared as an exported
    /// type in `project.yml` (`UTExportedTypeDeclarations`, conforms to `public.json`).
    static let gymPlan = UTType(exportedAs: "dev.abdirahmanmohamed.dagym.plan")
}

/// Wraps an encoded `.gymplan` file for `ShareLink` — written to a temp file on export since
/// `FileRepresentation` hands the share sheet a URL, not raw bytes.
struct PlanFile: Transferable {
    var data: Data
    var filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gymPlan) { file in
            SentTransferredFile(try file.temporaryFileURL())
        }
    }

    private func temporaryFileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("gymplan")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Wraps a rendered PDF for `ShareLink`, same temp-file mechanics as `PlanFile`.
struct PlanPDFFile: Transferable {
    var data: Data
    var filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            SentTransferredFile(try file.temporaryFileURL())
        }
    }

    private func temporaryFileURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
