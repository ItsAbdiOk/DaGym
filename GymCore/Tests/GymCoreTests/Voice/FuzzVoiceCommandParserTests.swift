import Foundation
import Testing
@testable import GymCore

/// Property test: `VoiceCommandParser.parse` and `LogCommandValidator.validate` never trap,
/// whatever the recogniser hands them. A speech recogniser is an adversarial input source — it
/// produces digit strings that are not numbers, grammar words in impossible orders, emoji from a
/// dictation keyboard, and utterances hundreds of words long — and a trap here is an app crash in
/// the middle of a workout. Iteration count follows `FuzzIterations` (`DAGYM_TEST_FUZZ_ITERATIONS`).
@Suite("Fuzz: voice command parser")
struct FuzzVoiceCommandParserTests {
    /// Every word the grammar knows, plus number words, units and a few exercise fragments, so
    /// random soups land inside the patterns rather than bouncing off the first guard.
    private static let vocabulary: [String] = [
        "bench", "press", "squat", "row", "plank", "pull", "ups", "curl", "dumbbell", "barbell",
        "one", "two", "three", "five", "eight", "ten", "twelve", "fifteen", "twenty", "forty",
        "sixty", "hundred", "thousand", "point", "and", "a", "an", "half", "quarter", "zero",
        "0", "1", "2", "8", "10", "60", "100", "225", "102.5", "1e6", "1e400", "-1", "-0", "nan",
        "inf", "99999999999999999999", "0x1p3", "٣", "٤٥", "３", "１２", "½", "¼", "×",
        "x", "for", "at", "reps", "rep", "sets", "set", "of", "kg", "kilos", "lb", "lbs", "pounds",
        "plate", "plates", "per", "side", "each", "arm", "seconds", "minutes", "second", "minute",
        "k", "km", "miles", "mile", "done", "next", "same", "again", "weight", "undo", "scrap",
        "that", "delete", "the", "last", "correct", "correction", "actually", "make", "it", "rate",
        "rpe", "rir", "in", "tank", "reserve", "left", "failure", "easy", "hard", "note", "swap",
        "add", "remove", "drop", "warm", "up", "rest", "timer", "pause", "skip", "what", "was",
        "my", "pr", "session", "time", "assisted", "band", "bodyweight", "run", "treadmill",
        "🏋️", "💪", "", " ", "\n", "\u{0}", "\u{FEFF}", "'s", "’s", "-", ".", ",", "?", "!"
    ]

    private static func soup(_ rng: inout FuzzRNG, maxWords: Int) -> String {
        let count = rng.int(maxWords + 1)
        var words: [String] = []
        words.reserveCapacity(count)
        for _ in 0..<count { words.append(rng.pick(vocabulary)) }
        let separators = [" ", "  ", " x ", ", ", " - ", "\t", "\u{00A0}"]
        return words.joined(separator: rng.pick(separators))
    }

    /// Random Unicode scalars: unpaired surrogates aren't representable in `String`, so this
    /// covers everything else — combining marks, RTL, emoji, private-use, control characters.
    private static func noise(_ rng: inout FuzzRNG) -> String {
        var scalars = String.UnicodeScalarView()
        for _ in 0..<(1 + rng.int(64)) {
            let value: UInt32 = rng.bool()
                ? UInt32(rng.int(0x80))
                : UInt32(rng.int(0x10FFFF))
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
        return String(scalars)
    }

    private static func contexts() -> [ParseContext] {
        [
            VoiceCommandParserFixtures.benchContext(),
            VoiceCommandParserFixtures.benchContext(unit: .lb, lastCompleted: false),
            VoiceCommandParserFixtures.plankContext(),
            // No on-deck, no session, no library: the state a lifter is in when they tap the
            // mic before adding an exercise.
            ParseContext(unit: .kg)
        ]
    }

    /// The whole voice pipeline, as the app runs it: parse, then validate every command the
    /// parse produced. Any trap fails the test; any return is fine.
    private static func exercise(_ text: String, in context: ParseContext) {
        let result = VoiceCommandParser.parse(text, context: context)
        #expect(result.confidence.isFinite)
        #expect(result.confidence >= 0 && result.confidence <= 1)
        for receipt in [false, true] {
            _ = LogCommandValidator.validate(result.commands, in: context, hasUndoReceipt: receipt)
        }
        // A bare `.logSet` may carry any set count from a parse — the validator caps it at 10,
        // so a parse must never have had to materialise a runaway number of sets to get there.
        for case .logSet(let spec) in result.commands {
            #expect(spec.sets.count <= MultiSetPattern.maxSpokenSets, "\(text)")
        }
    }

    @Test("grammar-word soups never trap")
    func grammarSoups() {
        var rng = FuzzRNG(seed: 0x5EED_0001)
        let contexts = Self.contexts()
        for iteration in 0..<FuzzIterations.count {
            let text = Self.soup(&rng, maxWords: 12)
            for context in contexts {
                Self.exercise(text, in: context)
            }
            _ = iteration
        }
    }

    @Test("long utterances never trap")
    func longUtterances() {
        var rng = FuzzRNG(seed: 0x5EED_0002)
        let contexts = Self.contexts()
        for _ in 0..<max(5, FuzzIterations.count / 10) {
            let text = Self.soup(&rng, maxWords: 400)
            for context in contexts {
                Self.exercise(text, in: context)
            }
        }
    }

    @Test("random Unicode never traps")
    func unicodeNoise() {
        var rng = FuzzRNG(seed: 0x5EED_0003)
        let contexts = Self.contexts()
        for _ in 0..<FuzzIterations.count {
            let text = Self.noise(&rng)
            for context in contexts {
                Self.exercise(text, in: context)
            }
        }
    }

    @Test("hand-picked hostile utterances never trap", arguments: [
        "", " ", "\n", "\u{0}", "undo", "scrap that", "delete the last set", "same again",
        "rate that a 12", "rpe 0", "rir -3", "rpe 10.5", "rpe nan", "1e400 for 8", "nan for nan",
        "99999999999999999999 sets of 8 at 60", "1000000 sets of 8", "0 sets of 0 at 0",
        "-5 for -8", "eight at minus five", "a plate and a half and a half and a half",
        "thousand thousand thousand thousand thousand thousand hundred hundred hundred",
        "225 x 8 x 8 x 8 x 8 x 8 x 8 x 8 x 8 x 8 x 8 x 8 x 8", "x", "x x x", "for", "at at at",
        "🏋️ 💪 🏋️", "١٠٠ for ٨", "１００ for ８", "½ ½ ½ ¼ ¼", "bench 72.5.5.5 for 8",
        "102.5kg×8", "60kgx8x3", "kgx", "xkg", "5k in 25 30", "ran 5 miles in 0 minutes",
        "run for 100000 minutes", "plank 1e6 seconds", "plank for a quarter",
        "correction 8 reps", "actually make it 1e6", "swap bench for", "add", "remove",
        "what was last session", "what's my pr on", "rest 0", "rest 1e6 seconds",
        "done done done", "next next", "bench", "press press press",
        String(repeating: "eight ", count: 2000), String(repeating: "a", count: 5000)
    ])
    func hostileUtterances(text: String) {
        for context in Self.contexts() {
            Self.exercise(text, in: context)
        }
    }
}
