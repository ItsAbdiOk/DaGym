import GymCore
import SwiftUI

/// Shows what a decoded `.gymplan` file will add before it's merged in — counts plus any
/// problems (an exercise slot that couldn't be resolved). Confirming calls `onConfirm`; the
/// merge itself never overwrites anything already in the store, and re-importing the same file
/// adds nothing new (plan.md §6.8).
struct PlanImportPreviewSheet: View {
    var document: PlanDocument
    var report: PlanImportReport
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            header
            // The problems list is unbounded (one entry per unresolved exercise slot), so it
            // scrolls inside a fixed sheet instead of overflowing a hard-coded height and pushing
            // the Import button off-screen — which is what a plan with four bad slots used to do.
            ScrollView {
                VStack(spacing: DGSpace.s5) {
                    countsCard
                    if !report.problems.isEmpty {
                        problemsCard
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
        .presentationDetents(report.problems.isEmpty ? [.height(320)] : [.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(document.program != nil ? "Import Program" : "Import Routine")
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
            Text(subtitle)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        let names = document.routines.map(\.name).joined(separator: ", ")
        return names.isEmpty ? "No routines in this file." : names
    }

    private var countsCard: some View {
        DGAdaptiveStack(spacing: 0, threshold: .accessibility3) {
            StatTile(value: "\(report.routinesImported)", label: "Routines")
            StatTile(value: "\(report.exercisesImported)", label: "Exercises")
            StatTile(value: report.programImported ? "Yes" : "No", label: "Program")
        }
        .dgCard(padding: 0)
    }

    private var problemsCard: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("\(report.problems.count) problem\(report.problems.count == 1 ? "" : "s")").dgLabel()
            VStack(alignment: .leading, spacing: DGSpace.s2) {
                ForEach(report.problems, id: \.self) { problem in
                    Text(problem)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
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
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            PlanImportPreviewSheet(
                document: PlanDocument(
                    exportedAt: Date(), appVersion: "1.0",
                    routines: [PlanRoutine(id: UUID(), name: "Push A")]
                ),
                report: PlanImportReport(
                    routinesImported: 1, exercisesImported: 2,
                    problems: ["Skipped \"Cable Fly\" in routine \"Push A\": exercise not found."]
                ),
                onConfirm: {}, onCancel: {}
            )
        }
}
