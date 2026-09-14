import Foundation

/// Turns one utterance (typed, dictated, from Siri, or from the watch) into a
/// `ParseResult`, trying the §4.5 grammar patterns in priority order and
/// stopping at the first match.
public enum VoiceCommandParser {
    /// Parses `text` against `context`. Returns an empty, zero-confidence
    /// result when nothing in the closed grammar matches.
    public static func parse(_ text: String, context: ParseContext) -> ParseResult {
        let words = Tokenizer.words(text)
        guard !words.isEmpty else { return ParseResult() }

        let attempts: [() -> ParseResult?] = [
            { MetaCorrectionRate.matchUndo(words) },
            { MetaCorrectionRate.matchCorrection(words, context: context) },
            { MetaCorrectionRate.matchRateLastSet(words) },
            { NoteQueryPattern.matchNote(words) },
            { RepeatPattern.match(words, context: context) },
            { RestPattern.match(words) },
            { SwapAddRemovePattern.match(words, context: context) },
            { NoteQueryPattern.matchQuery(words, context: context) },
            { CardioPattern.match(words, context: context) },
            { CompoundSplitPattern.match(words, context: context) },
            { MultiSetPattern.match(words, context: context) },
            { TimedPattern.match(words, context: context) },
            { SingleSetPattern.match(words, context: context) },
            { CompletionPattern.match(words) },
            { BareNumberPattern.match(words) }
        ]

        for attempt in attempts {
            if let result = attempt() {
                return result
            }
        }
        return ParseResult()
    }
}
