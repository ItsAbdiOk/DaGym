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
                Text("All done").dgLabel(DGColor.success)
                Text("\(setsDone) sets logged. Finish now, or keep going?")
                    .font(DGFont.subhead)
                    .foregroundStyle(DGColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DGSpace.s3) {
                DGPrimaryButton(
                    title: "Finish", symbol: "checkmark", fill: DGColor.success, height: 44, action: onFinish
                )
                Button(action: onKeepGoing) {
                    Text("Keep going")
                        .font(DGFont.condensedLabel(15))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DGColor.ink1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .dgGlass(.regular, in: Capsule())
                }
                .buttonStyle(DGPressStyle())
            }
        }
        .dgCard(
            radius: DGRadius.md, fill: DGColor.success.opacity(0.12),
            stroke: DGColor.success.opacity(0.35), padding: DGSpace.s4
        )
        .accessibilityIdentifier("workout.allDone")
    }
}
