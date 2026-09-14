import SwiftUI

/// "Add routine…" from the workout header menu: pick a saved routine and its exercises are
/// appended to the session, auto-filled the same way a fresh start is.
struct AddRoutineSheet: View {
    var routines: [RoutineInfo]
    var onPick: (RoutineInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DGSpace.s4) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
            Text("Add routine")
                .font(DGFont.title2)
                .textCase(.uppercase)
                .foregroundStyle(DGColor.ink1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if routines.isEmpty {
                EmptyState(
                    symbol: "list.bullet.rectangle", title: "No Routines Yet",
                    message: "Build one on the Routines tab and it'll show up here."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: DGSpace.s2) {
                        ForEach(routines) { routine in
                            row(routine)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s4)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(DGColor.surface1)
    }

    private func row(_ routine: RoutineInfo) -> some View {
        Button {
            onPick(routine)
            dismiss()
        } label: {
            HStack(spacing: DGSpace.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(DGFont.title3)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                    Text(summary(routine))
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink3)
                }
                Spacer(minLength: DGSpace.s2)
                Image(systemName: "plus")
                    .accessibilityHidden(true)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DGColor.coralText)
            }
            .padding(.horizontal, DGSpace.s4)
            .frame(minHeight: DGTap.rowHeight)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
        }
        .buttonStyle(.dgRow)
    }

    private func summary(_ routine: RoutineInfo) -> String {
        let count = routine.exercises.count
        let exercises = "\(count) exercise\(count == 1 ? "" : "s")"
        return "\(exercises) · \(routine.setCount) sets · ~\(routine.estimatedMinutes) min"
    }
}
