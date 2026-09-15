import GymCore
import SwiftUI

/// The workout debrief on `WorkoutSummaryView`: a score out of ten and three short lists,
/// streamed in from `CoachLanguageModel.debrief(facts:)`. Skeleton rows while the first
/// snapshot loads; the rule debrief if the model fails or is rejected; hidden altogether when
/// even the rules have nothing cited to say. Every bullet on screen has passed
/// `DebriefValidator` — the card never shows a claim that doesn't cite a fact it was given.
struct DebriefCard: View {
    var facts: SessionSummaryFacts

    @Environment(CoachServices.self) private var coach
    @State private var debrief: SessionDebrief?
    @State private var isHidden = false

    var body: some View {
        if !isHidden {
            VStack(alignment: .leading, spacing: DGSpace.s3) {
                header
                if let debrief {
                    lists(debrief)
                } else {
                    skeleton
                }
            }
            .padding(DGSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                    .strokeBorder(DGColor.hairline, lineWidth: 1)
            }
            .task { await load() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11yID.debriefCard)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Debrief").dgLabel()
            Spacer()
            if let score = debrief?.score {
                Text("\(score)/10")
                    .font(DGFont.title3)
                    .foregroundStyle(coach.isUsingLanguageModel ? DGColor.aiVioletText : DGColor.ink1)
                    .accessibilityLabel("Score \(score) out of 10")
            }
        }
    }

    private func lists(_ debrief: SessionDebrief) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s3) {
            list("Went well", debrief.wentWell)
            list("Watch", debrief.watch)
            list("Try next", debrief.tryNext)
            Text(coach.isUsingLanguageModel
                 ? "Written on your iPhone from this session's numbers. Nothing is sent anywhere."
                 : "From the rule-based coach. Nothing is sent anywhere.")
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ claims: [CoachClaim]) -> some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: DGSpace.s1) {
                Text(title)
                    .font(DGFont.condensedLabel(12))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(DGColor.ink3)
                ForEach(Array(claims.enumerated()), id: \.offset) { _, claim in
                    Text("• \(claim.text)")
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DGColor.surface3)
                    .frame(maxWidth: index == 2 ? 180 : .infinity)
                    .frame(height: 14)
            }
        }
        .accessibilityLabel("Writing the debrief")
    }

    /// Streams the model's debrief; on any failure shows the rule debrief instead, and hides
    /// the card when even that has nothing to say (`DebriefValidator` returned nil).
    private func load() async {
        do {
            for try await snapshot in coach.model.debrief(facts: facts) {
                debrief = snapshot
            }
        } catch {
            debrief = nil
        }
        if debrief == nil {
            debrief = DebriefValidator.validate(DebriefRules.debrief(from: facts), facts: facts)
        }
        isHidden = debrief == nil
    }
}
