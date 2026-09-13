import GymCore
import SwiftUI

/// Share icon for a routine or program (plan.md §6.8): a menu offering the `.gymplan` file
/// (share sheet/Messages/AirDrop — opening it on another device imports it) or a printable PDF.
/// Used from `RoutinesTabView` cards, `RoutineBuilderView`'s nav bar and `ProgramsView` rows —
/// callers pass `makeDocument` so this view stays agnostic of routines vs. programs.
struct ShareRoutineButton: View {
    var title: String
    var makeDocument: () -> PlanDocument?

    @State private var planFile: PlanFile?
    @State private var pdfFile: PlanPDFFile?

    var body: some View {
        Menu {
            if let planFile {
                ShareLink(item: planFile, preview: SharePreview(title)) {
                    Label("Share Plan File", systemImage: "square.and.arrow.up")
                }
            }
            if let pdfFile {
                ShareLink(item: pdfFile, preview: SharePreview(title)) {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DGColor.ink2)
                .frame(width: DGTap.min, height: DGTap.min)
        }
        .task { prepare() }
    }

    private func prepare() {
        guard let document = makeDocument() else { return }
        if let data = try? PlanCodec.encode(document) {
            planFile = PlanFile(data: data, filename: sanitizedFilename)
        }
        pdfFile = PlanPDFFile(data: PlanPDFRenderer.render(document), filename: sanitizedFilename)
    }

    private var sanitizedFilename: String {
        title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
    }
}

#Preview {
    ShareRoutineButton(title: "Push A") {
        PlanDocument(exportedAt: Date(), appVersion: "1.0")
    }
    .padding()
    .background(AmbientWash())
}
