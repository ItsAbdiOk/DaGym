import GymCore
import SwiftUI

/// Shows what a decoded backup file will add before it's merged in —
/// counts plus any problems (an exercise or routine slot that couldn't be
/// resolved). Confirming calls `onConfirm`; the merge itself never
/// overwrites anything already in the store.
struct ImportPreviewSheet: View {
    var document: BackupDocument
    var report: ImportReport
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            header
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
        .presentationDetents(report.problems.isEmpty ? [.medium] : [.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("Import Backup")
                .font(DGFont.title2)
                .foregroundStyle(DGColor.ink1)
            Text("Exported \(document.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countsCard: some View {
        DGAdaptiveStack(spacing: 0, threshold: .accessibility3) {
            StatTile(value: "\(report.workoutsImported)", label: "Workouts")
            StatTile(value: "\(report.routinesImported)", label: "Routines")
            StatTile(value: "\(report.exercisesImported)", label: "Exercises")
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
            ImportPreviewSheet(
                document: BackupDocument(
                    exportedAt: Date(), appVersion: "1.0", preferences: BackupPreferences()
                ),
                report: ImportReport(
                    exercisesImported: 2, routinesImported: 3, workoutsImported: 12,
                    problems: ["Skipped \"Cable Fly\" in routine \"Push A\": exercise not found."]
                ),
                onConfirm: {}, onCancel: {}
            )
        }
}
