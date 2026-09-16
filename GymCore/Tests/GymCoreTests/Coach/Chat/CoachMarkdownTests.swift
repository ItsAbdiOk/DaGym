import Testing

@testable import GymCore

@Suite("Coach markdown-lite")
struct CoachMarkdownTests {
    private typealias Inline = CoachMarkdown.Inline

    private func plain(_ text: String) -> [Inline] { [Inline(text)] }

    @Test("paragraphs join their lines; blank lines separate them")
    func paragraphs() {
        let blocks = CoachMarkdown.parse("First line\ncontinues here.\n\nLast.")
        #expect(blocks == [.paragraph(plain("First line continues here.")), .paragraph(plain("Last."))])
        #expect(CoachMarkdown.parse("").isEmpty)
        #expect(CoachMarkdown.parse("  \n\n ").isEmpty)
    }

    @Test("bold, italic and code become styled runs; mixed markers nest")
    func inlineStyles() {
        let blocks = CoachMarkdown.parse("Do **three** sets of *eight* at `RPE 8`, _easy_.")
        #expect(blocks == [.paragraph([
            Inline("Do "), Inline("three", style: .bold), Inline(" sets of "),
            Inline("eight", style: .italic), Inline(" at "), Inline("RPE 8", style: .code),
            Inline(", "), Inline("easy", style: .italic), Inline(".")
        ])])
        #expect(CoachMarkdown.parse("**bold *and italic* still bold**") == [.paragraph([
            Inline("bold ", style: .bold), Inline("and italic", style: [.bold, .italic]),
            Inline(" still bold", style: .bold)
        ])])
        #expect(CoachMarkdown.parse("***both***") == [.paragraph([Inline("both", style: [.bold, .italic])])])
    }

    @Test("stray asterisks and underscores in numbers and identifiers stay literal")
    func literalMarkers() {
        #expect(CoachMarkdown.parse("5 * 3 * 2 and 3*5") == [.paragraph(plain("5 * 3 * 2 and 3*5"))])
        #expect(CoachMarkdown.parse("target_reps and rest_seconds") == [
            .paragraph(plain("target_reps and rest_seconds"))
        ])
        #expect(CoachMarkdown.parse("keep \\*this\\* literal") == [.paragraph(plain("keep *this* literal"))])
        #expect(CoachMarkdown.parse("`a*b*c`") == [.paragraph([Inline("a*b*c", style: .code)])])
    }

    @Test("an unclosed marker styles the rest, so streaming never flickers; bold spans lines")
    func streamingTolerance() {
        #expect(CoachMarkdown.parse("Bench: **80 kg for") == [.paragraph([
            Inline("Bench: "), Inline("80 kg for", style: .bold)
        ])])
        #expect(CoachMarkdown.parse("**Bench is\nyour best** lift") == [.paragraph([
            Inline("Bench is your best", style: .bold), Inline(" lift")
        ])])
    }

    @Test("bullet lists accept every marker and survive blank lines between items")
    func bullets() {
        let text = "Plan:\n- one\n* two\n\n• three\n+ four\n\nDone."
        #expect(CoachMarkdown.parse(text) == [
            .paragraph(plain("Plan:")),
            .bullets([plain("one"), plain("two"), plain("three"), plain("four")]),
            .paragraph(plain("Done."))
        ])
    }

    @Test("numbered lists keep their start number and accept '1)' as well as '1.'")
    func numbered() {
        #expect(CoachMarkdown.parse("3. third\n4) fourth\n\n5. fifth") == [
            .numbered(start: 3, items: [plain("third"), plain("fourth"), plain("fifth")])
        ])
        #expect(CoachMarkdown.parse("1. a\n- b") == [
            .numbered(start: 1, items: [plain("a")]), .bullets([plain("b")])
        ])
        #expect(CoachMarkdown.parse("2024. was a year") == [.paragraph(plain("2024. was a year"))])
    }

    @Test("a plain line right after an item continues it; after a blank it is a paragraph")
    func lazyContinuation() {
        #expect(CoachMarkdown.parse("- one\nmore of one\n\nNext.") == [
            .bullets([plain("one more of one")]), .paragraph(plain("Next."))
        ])
    }

    @Test("headings become heading blocks; rules vanish; a bare hash is text")
    func headingsAndRules() {
        #expect(CoachMarkdown.parse("## Week 1\n---\ntext\n***\n### Notes **b**") == [
            .heading(plain("Week 1")), .paragraph(plain("text")),
            .heading([Inline("Notes "), Inline("b", style: .bold)])
        ])
        #expect(CoachMarkdown.parse("#hashtag") == [.paragraph(plain("#hashtag"))])
    }

    @Test("plain text strips markers and normalises list markers")
    func plainText() {
        let text = "**Bench**\n\n1. a\n2) b\n\n- c"
        #expect(CoachMarkdown.plainText(text) == "Bench\n\n1. a\n2. b\n\n• c")
        #expect(CoachMarkdown.Block.heading(plain("H")).plainText == "H")
    }

    @Test("long replies are those over the character or line budget")
    func isLong() {
        #expect(!CoachMarkdown.isLong("short"))
        #expect(CoachMarkdown.isLong(String(repeating: "a", count: 901)))
        #expect(CoachMarkdown.isLong(Array(repeating: "l", count: 13).joined(separator: "\n")))
        #expect(!CoachMarkdown.isLong(Array(repeating: "l", count: 12).joined(separator: "\n")))
    }

    @Test("a preview keeps whole blocks within budget and trims the one that crosses it at a word")
    func preview() {
        let long = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces)
        let blocks = CoachMarkdown.parse("Intro.\n\n- a\n- b\n\n\(long)\n\nTail.")
        let kept = CoachMarkdown.preview(blocks, budget: 120)
        #expect(kept.count == 3)
        guard case .paragraph(let inlines)? = kept.last else { Issue.record("expected a paragraph"); return }
        let text = CoachMarkdown.Block.plain(inlines)
        #expect(text.hasSuffix("word…"))
        #expect(text.count < 120)
        #expect(CoachMarkdown.preview(blocks, budget: 10) == [.paragraph(plain("Intro."))])
    }
}
