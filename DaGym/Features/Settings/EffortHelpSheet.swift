import SwiftUI

/// "What are RIR and RPE?" — reached from Settings' Effort section (OpenGym parity, features
/// "Adopt now" #18). Explains both scales in our own words; no OpenGym copy.
struct EffortHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpace.s6) {
                header
                explanation(
                    title: "RPE — Rate of Perceived Exertion",
                    body: "How hard a set felt, from 1 (barely any effort) to 10 (an all-out max "
                        + "effort with nothing left). Most working sets land between 6 and 9."
                )
                explanation(
                    title: "RIR — Reps in Reserve",
                    body: "How many more reps you could have done before failure. 0 RIR means "
                        + "the set was taken to failure; 2–3 RIR is a common working-set target."
                )
                explanation(
                    title: "They're two sides of the same scale",
                    body: "RPE 10 is 0 RIR, RPE 8 is about 2 RIR, and so on — pick whichever one "
                        + "is easier to judge mid-set; the app converts between them automatically."
                )
            }
            .padding(.horizontal, DGSpace.s5)
            .padding(.top, DGSpace.s6)
            .padding(.bottom, DGSpace.s8)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(DGColor.surface1)
    }

    private var header: some View {
        HStack {
            Text("RIR & RPE").font(DGFont.title2).foregroundStyle(DGColor.ink1)
            Spacer()
            DGIconButton(symbol: "xmark", accessibilityLabel: "Close") { dismiss() }
        }
    }

    private func explanation(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            Text(title).font(DGFont.title3).foregroundStyle(DGColor.ink1)
            Text(body).font(DGFont.body).foregroundStyle(DGColor.ink3)
        }
    }
}

#Preview {
    EffortHelpSheet()
}
