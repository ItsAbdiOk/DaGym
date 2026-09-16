import GymCore
import SwiftUI

/// Draws `CoachMarkdown` blocks: paragraphs and headings as attributed text, lists as rows
/// with a hanging marker (bullets, or right-aligned numbers so "9." and "10." line up).
/// Re-parses on every update — the parser is linear and a reply is a few kilobytes — but
/// keeps the last result by string identity so a streaming bubble that re-renders for an
/// unrelated state change does not parse twice. Each list item is one VoiceOver element.
struct CoachMarkdownText: View {
    var blocks: [CoachMarkdown.Block]
    var font: Font = DGFont.body
    var color: Color = DGColor.ink1

    init(blocks: [CoachMarkdown.Block], font: Font = DGFont.body, color: Color = DGColor.ink1) {
        self.blocks = blocks
        self.font = font
        self.color = color
    }

    init(_ text: String, font: Font = DGFont.body, color: Color = DGColor.ink1) {
        self.init(blocks: CoachMarkdownCache.parse(text), font: font, color: color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpace.s2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: CoachMarkdown.Block) -> some View {
        switch block {
        case .paragraph(let inlines):
            Text(attributed(inlines))
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let inlines):
            Text(attributed(inlines, base: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .bullets(let items):
            list(items, marker: { _ in "•" }, markerWidth: 12)
        case .numbered(let start, let items):
            list(items, marker: { "\($0 + start)." }, markerWidth: items.count + start > 10 ? 26 : 20)
        }
    }

    private func list(
        _ items: [[CoachMarkdown.Inline]], marker: @escaping (Int) -> String, markerWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: DGSpace.s1) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: DGSpace.s2) {
                    Text(marker(index))
                        .font(font)
                        .foregroundStyle(DGColor.ink3)
                        .frame(width: markerWidth, alignment: .trailing)
                    Text(attributed(item))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(marker(index)) \(CoachMarkdown.Block.plain(item))")
            }
        }
    }

    /// One `AttributedString` per line: the run's style picks the font variant, code gets a
    /// monospaced face on a faint wash.
    private func attributed(
        _ inlines: [CoachMarkdown.Inline], base: CoachMarkdown.Inline.Style = []
    ) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            var run = AttributedString(inline.text)
            let style = inline.style.union(base)
            var runFont = font
            if style.contains(.bold) { runFont = runFont.bold() }
            if style.contains(.italic) { runFont = runFont.italic() }
            if style.contains(.code) {
                runFont = runFont.monospaced()
                run.backgroundColor = DGColor.surface3
            }
            run.font = runFont
            run.foregroundColor = color
            result.append(run)
        }
        return result
    }
}

/// Recent parses keyed by the text itself. Every visible bubble's body runs on every streamed
/// delta and on every unrelated screen update; only the one bubble whose text changed should
/// parse. Bounded by dropping everything past a few dozen entries — a thread has that many
/// bubbles on screen at most, and a miss only costs one linear parse.
@MainActor
enum CoachMarkdownCache {
    private static var blocksByText: [String: [CoachMarkdown.Block]] = [:]
    private static let capacity = 64

    static func parse(_ text: String) -> [CoachMarkdown.Block] {
        if let cached = blocksByText[text] { return cached }
        let blocks = CoachMarkdown.parse(text)
        if blocksByText.count >= capacity { blocksByText.removeAll(keepingCapacity: true) }
        blocksByText[text] = blocks
        return blocks
    }
}

#Preview {
    CoachMarkdownText(
        """
        ## Week one
        Bench is your **best lift**: 80 kg for *five* on 12 Sep.

        1. Keep the top set at `RPE 8`
        2. Add a back-off set

        - Rows twice a week
        - Rest 2 min
        """
    )
    .padding()
    .background(AmbientWash())
}
