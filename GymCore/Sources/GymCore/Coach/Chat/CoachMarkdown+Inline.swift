import Foundation

/// The inline half of `CoachMarkdown`: one line of text into styled runs. A single left-to-right
/// pass with a style state; markers toggle it. `**` opens bold only when the next character is
/// not a space and closes only after a non-space, so "5 * 3 * 2" stays literal; `_` never
/// opens inside a word, so snake_case survives. Backslash escapes the next marker. A marker
/// left open at the end styles the rest of the line — right for streaming, where the closing
/// `**` is a few deltas away.
extension CoachMarkdown {
    static func inlines(_ text: String) -> [Inline] {
        var scanner = InlineScanner(Array(text))
        return scanner.scan()
    }

    private struct InlineScanner {
        private let chars: [Character]
        private var index = 0
        private var style: Inline.Style = []
        private var current = ""
        private var runs: [Inline] = []

        init(_ chars: [Character]) {
            self.chars = chars
        }

        mutating func scan() -> [Inline] {
            while index < chars.count {
                let char = chars[index]
                if char == "\\", let next = peek(1), "*_`\\".contains(next) {
                    current.append(next)
                    index += 2
                } else if char == "`" {
                    toggle(.code)
                    index += 1
                } else if style.contains(.code) {
                    current.append(char)
                    index += 1
                } else if char == "*", peek(1) == "*", peek(2) == "*", toggles([.bold, .italic], width: 3) {
                    toggle([.bold, .italic])
                    index += 3
                } else if char == "*", peek(1) == "*" {
                    if toggles(.bold, width: 2) { toggle(.bold) } else { current += "**" }
                    index += 2
                } else if char == "*" || char == "_" {
                    if toggles(.italic, width: 1, marker: char) {
                        toggle(.italic)
                    } else {
                        current.append(char)
                    }
                    index += 1
                } else {
                    current.append(char)
                    index += 1
                }
            }
            flush()
            return runs
        }

        private func peek(_ offset: Int) -> Character? {
            let at = index + offset
            return at >= 0 && at < chars.count ? chars[at] : nil
        }

        /// Whether the marker at `index` opens (when `style` lacks it) or closes (when it has
        /// it) the style, by the whitespace rules in the type comment.
        private func toggles(_ candidate: Inline.Style, width: Int, marker: Character = "*") -> Bool {
            let before = peek(-1)
            let after = peek(width)
            if style.contains(candidate) {
                guard let before, !before.isWhitespace else { return false }
                return marker != "_" || !(after?.isLetter ?? false)
            }
            guard let after, !after.isWhitespace, after != marker else { return false }
            if marker == "_" { return !(before?.isLetter ?? false) }
            return !(before?.isNumber ?? false) && !(before?.isLetter ?? false)
        }

        private mutating func toggle(_ candidate: Inline.Style) {
            flush()
            style.formSymmetricDifference(candidate)
        }

        private mutating func flush() {
            if !current.isEmpty { runs.append(Inline(current, style: style)) }
            current = ""
        }
    }
}
