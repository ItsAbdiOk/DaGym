import SwiftUI

/// The Coach tab until Phase 6 lands: an honest "not built yet" card laid out like every other
/// tab (wash behind, content clear of the floating tab bar) rather than a bare empty state.
struct CoachPlaceholderView: View {
    var body: some View {
        ZStack {
            AmbientWash()
            VStack(alignment: .leading, spacing: DGSpace.s5) {
                Text("Coach")
                    .font(DGFont.title1)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink1)
                EmptyState(
                    symbol: "sparkles",
                    title: "Coach Is On The Way",
                    message: "Program generation, mid-workout swaps and post-workout debriefs — "
                        + "all on your phone, nothing sent anywhere. Not in this build yet."
                )
                Spacer()
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.top, DGSpace.s3)
            .padding(.bottom, 120)
        }
    }
}

#Preview {
    CoachPlaceholderView()
}
