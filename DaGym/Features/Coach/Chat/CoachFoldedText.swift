import GymCore
import SwiftUI

/// A reply that folds when it is long: the first few hundred characters' worth of blocks
/// under a fade, then "Show more"; expanded, the whole thing and "Show less". Short text and
/// text that must stay open (`canFold` false — the turn still streaming) draw plainly. The
/// screen owns the expanded set per message id so a fold survives scrolling out of a
/// `LazyVStack` and back.
struct CoachFoldedText: View {
    var text: String
    var canFold: Bool
    @Binding var isExpanded: Bool
    var font: Font = DGFont.body
    var color: Color = DGColor.ink1

    private var blocks: [CoachMarkdown.Block] { CoachMarkdownCache.parse(text) }
    private var isFolded: Bool { canFold && !isExpanded && CoachMarkdown.isLong(text) }
    private var showsToggle: Bool { canFold && CoachMarkdown.isLong(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            if isFolded {
                CoachMarkdownText(blocks: CoachMarkdown.preview(blocks), font: font, color: color)
                    .mask(fade)
            } else {
                CoachMarkdownText(blocks: blocks, font: font, color: color)
            }
            if showsToggle {
                Button {
                    withAnimation(DGMotion.standard) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: DGSpace.s1) {
                        Text(isExpanded ? "Show less" : "Show more")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(DGFont.condensedLabel(12))
                    .foregroundStyle(DGColor.aiVioletText)
                    .frame(minHeight: DGTap.min)
                }
                .buttonStyle(.dgControl)
                .accessibilityLabel(isExpanded ? "Show less of this reply" : "Show the whole reply")
                .accessibilityIdentifier(A11yID.coachChatShowMore)
            }
        }
    }

    /// Solid until the last few lines, then out — so the cut reads as "continues" rather than
    /// as a sentence that stops.
    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0), .init(color: .black, location: 0.7),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}
