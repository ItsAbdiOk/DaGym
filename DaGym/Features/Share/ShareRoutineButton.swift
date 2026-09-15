import GymCore
import SwiftUI

/// Share icon for a routine or program (plan.md §6.8): a menu offering the `.gymplan` file
/// (share sheet/Messages/AirDrop — opening it on another device imports it) or a printable PDF.
/// Used from `RoutinesTabView` cards, `RoutineBuilderView`'s nav bar and `ProgramsView` rows —
/// callers pass `makeDocument` so this view stays agnostic of routines vs. programs. Its `Bool`
/// is `includeWeights`: the PDF is the lifter's own printout, so it carries their working
/// weights; the plan file goes to someone else, so it does not. The file and the PDF are only
/// built when the menu is opened, not for every card on every appearance.
struct ShareRoutineButton: View {
    @Environment(Preferences.self) private var preferences
    var title: String
    var makeDocument: (_ includeWeights: Bool) -> PlanDocument?

    var body: some View {
        Menu {
            // `Menu` builds its content when it opens, so the encode + PDF render run once per
            // open rather than once per card per appearance.
            ShareMenuItems(
                title: title, filename: sanitizedFilename, planDocument: makeDocument(false),
                pdfDocument: makeDocument(true), unit: preferences.weightUnit
            )
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DGColor.ink2)
                .frame(width: DGTap.min, height: DGTap.min)
        }
        .accessibilityLabel("Share \(title)")
    }

    private var sanitizedFilename: String {
        title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
    }
}

/// The two share rows, with their files built in `init` — i.e. when the menu opens.
private struct ShareMenuItems: View {
    var title: String
    private let planFile: PlanFile?
    private let pdfFile: PlanPDFFile?

    init(
        title: String, filename: String, planDocument: PlanDocument?, pdfDocument: PlanDocument?,
        unit: WeightUnit
    ) {
        self.title = title
        planFile = planDocument.flatMap { try? PlanCodec.encode($0) }.map {
            PlanFile(data: $0, filename: filename)
        }
        pdfFile = pdfDocument.map {
            PlanPDFFile(data: PlanPDFRenderer.render($0, unit: unit), filename: filename)
        }
    }

    var body: some View {
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
    }
}

#Preview {
    ShareRoutineButton(title: "Push A") { _ in
        PlanDocument(exportedAt: Date(), appVersion: "1.0")
    }
    .padding()
    .background(AmbientWash())
}
