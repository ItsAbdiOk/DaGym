import SwiftUI

/// The second opinion on the drafter's card: a green tick with the reviewer's reasons and
/// confidence when it agreed, a violet pointer to the alternative card below when it
/// proposed its own version, a muted mark when the review failed (the card stays usable).
struct CoachDraftReviewStrip: View {
    var strip: CoachReviewCopy.Strip

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            HStack(spacing: DGSpace.s2) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(strip.title)
                    .font(DGFont.condensedLabel(12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(tint)
            switch strip {
            case .agreed(_, let reasons, let confidence):
                ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                    HStack(alignment: .top, spacing: DGSpace.s2) {
                        Text("•").font(DGFont.footnote).foregroundStyle(DGColor.ink4)
                        Text(reason)
                            .font(DGFont.footnote)
                            .foregroundStyle(DGColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(confidence)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink4)
            case .failed(_, let reason):
                if !reason.isEmpty {
                    Text(reason)
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .alternative:
                EmptyView()
            }
        }
        .padding(DGSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: DGRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yID.coachChatDraftReview)
    }

    private var symbol: String {
        switch strip {
        case .agreed: "checkmark.circle.fill"
        case .alternative: "arrow.down.circle"
        case .failed: "exclamationmark.circle"
        }
    }

    private var tint: Color {
        switch strip {
        case .agreed: DGColor.success
        case .alternative: DGColor.aiVioletText
        case .failed: DGColor.ink4
        }
    }
}

#Preview {
    VStack(spacing: DGSpace.s3) {
        CoachDraftReviewStrip(strip: .agreed(
            title: "Opus agrees", reasons: ["Matches your volume", "Loads are conservative"],
            confidence: "High confidence"
        ))
        CoachDraftReviewStrip(strip: .alternative(title: "Opus proposed a change — see below"))
        CoachDraftReviewStrip(strip: .failed(title: "Opus couldn't review this", reason: "No connection"))
    }
    .padding()
    .background(AmbientWash())
}
