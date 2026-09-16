import GymCore
import SwiftUI

/// The four starter plans as tappable rows — the body of Home's `StarterPlanCard` and of the
/// `StarterPlanPickerSheet` the Routines tab's empty state opens, so both offer the same list
/// and the same one-tap adoption (`WorkoutStore.adoptStarterPlan`).
struct StarterPlanList: View {
    var onPick: (StarterProgramKind) -> Void
    /// Home's coral-washed card sits the rows on `surface1`; the sheet, itself `surface1`,
    /// needs one step darker for them to read as rows at all.
    var rowFill: Color = DGColor.surface1

    var body: some View {
        VStack(spacing: DGSpace.s2) {
            ForEach(StarterProgramKind.allCases) { kind in
                Button { onPick(kind) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.rawValue).font(DGFont.body).foregroundStyle(DGColor.ink1)
                            Text(kind.summary).font(DGFont.footnote).foregroundStyle(DGColor.ink3)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DGColor.ink4)
                    }
                    .padding(.horizontal, DGSpace.s4)
                    .frame(minHeight: 48)
                    .background(rowFill, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
                }
                .buttonStyle(.dgRow)
                .accessibilityLabel("\(kind.rawValue), \(kind.summary)")
                .accessibilityIdentifier(A11yID.starterPlan(kind.rawValue))
            }
        }
    }
}

/// "Load a starter plan" as a sheet (OpenGym parity 36): the Routines tab's empty state opens
/// it; picking a plan adopts it and dismisses.
struct StarterPlanPickerSheet: View {
    var onPick: (StarterProgramKind) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DGSpace.s4) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .padding(.top, DGSpace.s2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                Text("Pick a Starter Plan")
                    .font(DGFont.title2)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                Text("Its routines are added to this tab and the program starts today. "
                    + "Edit any of them afterwards.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StarterPlanList(
                onPick: { kind in
                    onPick(kind)
                    dismiss()
                },
                rowFill: DGColor.surface2
            )
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(440), .large])
        .presentationDragIndicator(.hidden)
    }
}

extension StarterProgramKind {
    /// The one-line "days × weeks" under each row.
    var summary: String {
        "\(routineNames.count) days · \(weeks)-week cycle with a deload"
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            StarterPlanPickerSheet { _ in }
        }
}
