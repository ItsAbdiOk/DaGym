import SwiftUI

/// Shown once the last planned set is ticked: finish now, or keep the session open to add
/// more. Inline, never a modal — a lifter who wants one more set shouldn't have to dismiss
/// anything.
struct AllDoneBanner: View {
    var setsDone: Int
    var onFinish: () -> Void
    var onKeepGoing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All done").dgLabel(DGColor.coralText)
                Text("\(setsDone) sets logged. Finish now, or keep going?")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            DGAdaptiveStack(spacing: DGSpace.s3) {
                Button(action: onFinish) {
                    Text("Finish")
                        .font(DGFont.condensedLabel(13.5))
                        .foregroundStyle(DGColor.inkOnCoral)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            DGColor.coral, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous)
                        )
                }
                .buttonStyle(.dgControl)
                WorkoutPillButton(title: "Keep going", style: .ink, radius: DGRadius.sm, action: onKeepGoing)
            }
        }
        .dgCard(radius: DGRadius.lg, padding: DGSpace.s4)
        .accessibilityIdentifier("workout.allDone")
    }
}
