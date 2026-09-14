/// The auto-log gate — the one place that decides whether an utterance may write to the training
/// log without the user seeing it first.
///
/// **What the confidence number means.** Two independent things can go wrong between a spoken set
/// and a logged one, and each has its own number:
///
/// * `parser` — `ParseResult.confidence`: how cleanly the closed grammar matched the *words*.
///   On its own it means very little: `SingleSetPattern` returns exactly 0.90 for any two-number
///   utterance with no exercise name, so "225 for 8" and "2 for 8" score identically.
/// * `recognition` — `SpeechTranscript.confidence`: the mean `SFTranscriptionSegment.confidence`
///   of the recognizer's *final* hypothesis, i.e. how sure it is those were the words said. This
///   is the leg that catches a truncated or misheard number, and it exists only on a final
///   result — which is why the release path waits for one instead of parsing the last partial.
///
/// They answer different questions, so `combined` takes the `min`: the gate is "**both** are at
/// least this sure", and the weaker leg is the one that can be wrong. A missing recognition
/// confidence is *unknown*, not low — and unknown is never eligible.
enum VoiceAutoLogPolicy {
    /// Both legs must reach this. Deliberately high (well above `ExerciseMatcher.threshold`'s
    /// 0.82) because auto-logging silently mutates the workout — there is no "are you sure"
    /// between the parse and the write.
    static let minConfidence = 0.90

    /// The combined score, or `nil` when there is no recognition confidence to combine — no
    /// final hypothesis arrived, or the recognizer reported 0 (which Apple uses for "unknown",
    /// including on every partial and on some locales/devices even for a final).
    static func combined(parser: Double, recognition: Double?) -> Double? {
        guard let recognition, recognition > 0 else { return nil }
        return min(parser, recognition)
    }
}
