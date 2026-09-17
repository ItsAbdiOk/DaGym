import GymCore
import SwiftUI

/// Detail card for one muscle, opened by tapping the map or a list row: how much recent work
/// it has taken, when that reading eases off, and which exercises put it there. The header used
/// to print "N % recovered" — false precision, and a claim about the lifter's body that an
/// effort-weighted set count decaying on a fixed curve cannot support. See
/// `MuscleRecovery.workloadLabel`.
struct MuscleDetailSheet: View {
    var recovery: MuscleRecovery

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s5) {
            Capsule()
                .fill(DGColor.ink4)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, DGSpace.s2)
            header
            recoveredByRow
            contributors
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.bottom, DGSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DGColor.surface1)
        .clipShape(RoundedRectangle(cornerRadius: DGRadius.sheet, style: .continuous))
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(recovery.muscle.displayName)
                .font(DGFont.title2)
                .foregroundStyle(DGColor.ink1)
            Spacer()
            Text(recovery.workloadLabel)
                .font(DGFont.subhead)
                .foregroundStyle(DGColor.ink3)
        }
        .accessibilityElement(children: .combine)
    }

    private var recoveredByRow: some View {
        HStack(spacing: DGSpace.s2) {
            Image(systemName: "clock").font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(recoveredByText)
        }
        .font(DGFont.footnote)
        .foregroundStyle(DGColor.coralText)
    }

    private var recoveredByText: String { recovery.easesOffSentence }

    private var contributors: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text("What fatigued it").dgLabel()
            if recovery.contributors.isEmpty {
                Text("No recent sets logged.")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink3)
            } else {
                VStack(spacing: DGSpace.s1) {
                    ForEach(recovery.contributors) { contributor in
                        HStack {
                            Text(contributor.exerciseName)
                                .font(DGFont.body)
                                .foregroundStyle(DGColor.ink2)
                            Spacer()
                            Text("\(contributor.sets) sets")
                                .font(DGFont.footnote)
                                .foregroundStyle(DGColor.ink3)
                        }
                        .frame(minHeight: 28)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

#Preview {
    MuscleDetailSheet(
        recovery: MuscleRecovery(
            muscle: .chest, fatigue: 1.2, spent: 0.7,
            recoveredBy: Date().addingTimeInterval(3600 * 20),
            contributors: [
                .init(exerciseName: "Bench Press", sets: 5, date: Date()),
                .init(exerciseName: "Incline DB Press", sets: 4, date: Date())
            ]
        )
    )
}
