import Foundation

/// Markdown-lite for what the chat models actually write: paragraphs, `**bold**`,
/// `*italic*`/`_italic_`, inline `code`, bullet and numbered lists, `##` headings (drawn as a
/// bold line) and horizontal rules (dropped). Tolerant by design — the house rules ask for
/// plain text, but the models slip into markdown anyway, and half-rendered markers read worse
/// than either extreme. Streaming-safe: an unclosed `**` styles the rest of the paragraph, so
/// text does not flicker between plain and bold as the closing marker arrives. Pure and
/// linear in the text length, so the bubble can re-parse on every streamed delta.
public enum CoachMarkdown {
    /// One styled run of a line. Styles combine (`***both***`, code inside bold), so this is a
    /// set rather than an enum.
    public struct Inline: Hashable, Sendable {
        public struct Style: OptionSet, Hashable, Sendable {
            public let rawValue: UInt8

            public init(rawValue: UInt8) { self.rawValue = rawValue }

            public static let bold = Style(rawValue: 1)
            public static let italic = Style(rawValue: 2)
            public static let code = Style(rawValue: 4)
        }

        public var text: String
        public var style: Style

        public init(_ text: String, style: Style = []) {
            self.text = text
            self.style = style
        }
    }

    public enum Block: Hashable, Sendable {
        case paragraph([Inline])
        case heading([Inline])
        case bullets([[Inline]])
        /// `start` is the first item's number, so "3." starts a list at 3 rather than 1.
        case numbered(start: Int, items: [[Inline]])

        /// The block's words without markers — what VoiceOver reads and Copy writes.
        public var plainText: String {
            switch self {
            case .paragraph(let inlines), .heading(let inlines): Self.plain(inlines)
            case .bullets(let items): items.map { "• " + Self.plain($0) }.joined(separator: "\n")
            case .numbered(let start, let items):
                items.enumerated().map { "\($0.offset + start). " + Self.plain($0.element) }
                    .joined(separator: "\n")
            }
        }

        public static func plain(_ inlines: [Inline]) -> String { inlines.map(\.text).joined() }
    }

    // MARK: - Blocks

    public static func parse(_ text: String) -> [Block] {
        var builder = BlockBuilder()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            builder.add(line: rawLine.trimmingCharacters(in: .whitespaces))
        }
        return builder.finish()
    }

    /// `parse` with the markers stripped: the reply as one copyable string, list markers
    /// normalised to "•" and "1.".
    public static func plainText(_ text: String) -> String {
        parse(text).map(\.plainText).joined(separator: "\n\n")
    }

    /// Whether a reply is long enough that the bubble should fold it behind "Show more":
    /// roughly a dozen lines or a few paragraphs of prose.
    public static func isLong(_ text: String, maxCharacters: Int = 900, maxLines: Int = 12) -> Bool {
        text.count > maxCharacters
            || text.split(separator: "\n", omittingEmptySubsequences: false).count > maxLines
    }

    /// The first `budget` characters' worth of blocks, cut at the block that crosses the line
    /// (its own text trimmed with an ellipsis). What a folded bubble shows above the fade.
    public static func preview(_ blocks: [Block], budget: Int = 420) -> [Block] {
        var used = 0
        var kept: [Block] = []
        for block in blocks {
            let length = block.plainText.count
            if used + length <= budget {
                kept.append(block)
                used += length
                continue
            }
            if case .paragraph(let inlines) = block, budget - used > 80 {
                kept.append(.paragraph(truncate(inlines, to: budget - used)))
            }
            break
        }
        return kept
    }

    private static func truncate(_ inlines: [Inline], to limit: Int) -> [Inline] {
        var remaining = limit
        var result: [Inline] = []
        for inline in inlines {
            if inline.text.count <= remaining {
                result.append(inline)
                remaining -= inline.text.count
            } else {
                let cut = inline.text.prefix(remaining)
                let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
                result.append(Inline(String(atWord) + "…", style: inline.style))
                return result
            }
        }
        return result
    }

    // MARK: - Line classification

    enum Line: Equatable {
        case blank
        case rule
        case heading(String)
        case bullet(String)
        case numbered(Int, String)
        case text(String)
    }

    static func classify(_ line: String) -> Line {
        if line.isEmpty { return .blank }
        if isRule(line) { return .rule }
        let hashes = line.prefix { $0 == "#" }
        if !hashes.isEmpty, hashes.count <= 6, line.dropFirst(hashes.count).first == " " {
            return .heading(line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces))
        }
        for marker in ["- ", "* ", "• ", "+ "] where line.hasPrefix(marker) {
            return .bullet(line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, let number = Int(digits) {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return .numbered(number, rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
        }
        return .text(line)
    }

    /// `---`, `***`, `___` (three or more, spaces allowed) — a rule, dropped.
    private static func isRule(_ line: String) -> Bool {
        let marks = line.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// Accumulates lines into blocks. Adjacent list items separated by blank lines still form
    /// one list (the models double-space them); a plain line straight after a list item is
    /// that item's continuation, as in CommonMark's lazy continuation.
    struct BlockBuilder {
        private struct List {
            var start: Int?
            var items: [String]
        }

        private var blocks: [Block] = []
        private var paragraph: [String] = []
        private var list: List?
        private var sawBlankSinceList = false

        mutating func add(line: String) {
            switch CoachMarkdown.classify(line) {
            case .blank:
                flushParagraph()
                sawBlankSinceList = true
            case .rule:
                flushParagraph()
                flushList()
            case .heading(let text):
                flushParagraph()
                flushList()
                blocks.append(.heading(CoachMarkdown.inlines(text)))
            case .bullet(let text):
                flushParagraph()
                append(item: text, numbered: nil)
            case .numbered(let number, let text):
                flushParagraph()
                append(item: text, numbered: number)
            case .text(let text):
                if var current = list, !sawBlankSinceList, paragraph.isEmpty {
                    current.items[current.items.count - 1] += " " + text
                    list = current
                } else {
                    flushList()
                    paragraph.append(text)
                }
            }
        }

        mutating func finish() -> [Block] {
            flushParagraph()
            flushList()
            return blocks
        }

        private mutating func append(item: String, numbered: Int?) {
            if var current = list, (current.start == nil) == (numbered == nil) {
                current.items.append(item)
                list = current
            } else {
                flushList()
                list = List(start: numbered, items: [item])
            }
            sawBlankSinceList = false
        }

        private mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(CoachMarkdown.inlines(paragraph.joined(separator: " "))))
            paragraph = []
        }

        private mutating func flushList() {
            guard let list else { return }
            let items = list.items.map(CoachMarkdown.inlines)
            blocks.append(list.start.map { .numbered(start: $0, items: items) } ?? .bullets(items))
            self.list = nil
            sawBlankSinceList = false
        }
    }
}
