import Foundation
import Testing
@testable import GymCore

/// The fifteen utterances the deep review hand-traced (docs/reviews/voice.md §3):
/// each asserts the exercise, the numbers, and the validator's verdict.
@Suite("VoiceCommandParser traced utterances")
struct VoiceCommandParserTracedTests {
    typealias Fixtures = VoiceCommandParserFixtures

    enum Context: Sendable { case bench, benchLb, pullUpsOnDeck }
    enum Exercise: Sendable, Equatable { case onDeck, id(UUID) }
    enum Verdict: Sendable { case success, needsDisambiguation, implausibleWeight }

    struct Traced: Sendable, CustomTestStringConvertible {
        var utterance: String
        var context: Context = .bench
        var command: String
        var exercise: Exercise = .onDeck
        var sets: [LogSetSpec.SetValues] = []
        var effort: Effort?
        var isPerSide: Bool?
        var overrides: LogSetSpec.Overrides?
        var restSeconds: Int?
        var verdict: Verdict = .success
        var testDescription: String { utterance }
    }

    static let rows: [Traced] = [
        Traced(
            utterance: "lateral raises twelve at ten", command: "logSet",
            exercise: .id(Fixtures.sideLateralRaiseID), sets: [.init(reps: 12, weightKg: 10)]
        ),
        Traced(
            utterance: "did eight at a hundred.", command: "logSet", sets: [.init(reps: 8, weightKg: 100)]
        ),
        Traced(
            utterance: "10, 10, 8 at 80", command: "logSet",
            sets: [.init(reps: 10, weightKg: 80), .init(reps: 10, weightKg: 80), .init(reps: 8, weightKg: 80)]
        ),
        Traced(
            utterance: "two twenty five for eight", context: .benchLb, command: "logSet",
            sets: [.init(reps: 8, weightKg: WeightUnit.lb.toKg(225))]
        ),
        Traced(
            utterance: "same again but at ninety", command: "repeatPrevious", overrides: .init(weightKg: 90)
        ),
        Traced(
            utterance: "squats five by five at one forty", command: "logSet", exercise: .id(Fixtures.squatID),
            sets: Array(repeating: .init(reps: 5, weightKg: 140), count: 5)
        ),
        Traced(
            utterance: "three sets of eight squats at sixty", command: "logSet",
            exercise: .id(Fixtures.squatID), sets: Array(repeating: .init(reps: 8, weightKg: 60), count: 3)
        ),
        Traced(
            utterance: "twelve bodyweight", command: "logSet", sets: [.init(reps: 12, isBodyweight: true)]
        ),
        Traced(utterance: "add easy bar curls", command: "addExercise", verdict: .needsDisambiguation),
        // Per-side parses; 12 kg cannot go on the on-deck barbell, so the validator
        // refuses it rather than snapping it to an empty bar.
        Traced(
            utterance: "eight each leg at twelve", command: "logSet",
            sets: [.init(reps: 8, weightKg: 12)], isPerSide: true, verdict: .implausibleWeight
        ),
        Traced(
            utterance: "bench eight at a hundred", context: .pullUpsOnDeck, command: "logSet",
            exercise: .id(Fixtures.benchID), sets: [.init(reps: 8, weightKg: 100)]
        ),
        Traced(
            utterance: "plank ninety seconds", command: "logSet", exercise: .id(Fixtures.plankID),
            sets: [.init(durationSeconds: 90)]
        ),
        Traced(utterance: "rest a minute and a half", command: "rest", restSeconds: 90),
        Traced(utterance: "a hundred for eight", command: "logSet", sets: [.init(reps: 8, weightKg: 100)]),
        Traced(
            utterance: "eight reps at sixty kilos felt like a nine", command: "logSet",
            sets: [.init(reps: 8, weightKg: 60)], effort: Effort(rpe: 9)
        )
    ]

    private static func context(_ kind: Context) -> ParseContext {
        switch kind {
        case .bench: Fixtures.benchContext()
        case .benchLb: Fixtures.benchContext(unit: .lb)
        case .pullUpsOnDeck: Fixtures.pullUpsContext()
        }
    }

    @Test("parse and validate", arguments: rows)
    func parseAndValidate(_ row: Traced) throws {
        let context = Self.context(row.context)
        let result = VoiceCommandParser.parse(row.utterance, context: context)
        let command = try #require(result.commands.first, "nothing parsed")

        switch command {
        case .logSet(let spec):
            #expect(row.command == "logSet")
            check(spec, against: row)
        case .repeatPrevious(let overrides):
            #expect(row.command == "repeatPrevious")
            #expect(overrides == row.overrides)
        case .rest(let action):
            #expect(row.command == "rest")
            #expect(action == .start(seconds: row.restSeconds))
        case .addExercise:
            #expect(row.command == "addExercise")
        default:
            Issue.record("unexpected \(command)")
        }

        let validated = LogCommandValidator.validate(result.commands, in: context)
        switch (row.verdict, validated) {
        case (.success, .success(let commands)):
            #expect(commands.count == result.commands.count)
            #expect(result.confidence >= 0.8)
        case (.needsDisambiguation, .failure(.needsDisambiguation)),
             (.implausibleWeight, .failure(.implausibleWeight)):
            break
        default:
            Issue.record("expected \(row.verdict), got \(validated)")
        }
    }

    private func check(_ spec: LogSetSpec, against row: Traced) {
        switch (row.exercise, spec.exercise) {
        case (.onDeck, .none), (.onDeck, .onDeck): break
        case (.id(let expected), .id(let actual)): #expect(actual == expected)
        default: Issue.record("expected exercise \(row.exercise), got \(String(describing: spec.exercise))")
        }
        #expect(spec.sets.count == row.sets.count)
        for (actual, expected) in zip(spec.sets, row.sets) {
            #expect(actual.reps == expected.reps)
            #expect(actual.durationSeconds == expected.durationSeconds)
            #expect(actual.isBodyweight == expected.isBodyweight)
            #expect(actual.assistanceKg == expected.assistanceKg)
            #expect(actual.addedKg == expected.addedKg)
            switch (actual.weightKg, expected.weightKg) {
            case (.none, .none): break
            case (.some(let lhs), .some(let rhs)): #expect(abs(lhs - rhs) < 0.05)
            default:
                let got = String(describing: actual.weightKg)
                Issue.record("weight \(got) ≠ \(String(describing: expected.weightKg))")
            }
        }
        #expect(spec.effort == row.effort)
        if let isPerSide = row.isPerSide { #expect(spec.isPerSide == isPerSide) }
    }
}

/// Regressions for the grammar fixes around the traced set.
@Suite("VoiceCommandParser grammar fixes")
struct VoiceCommandParserGrammarTests {
    typealias Fixtures = VoiceCommandParserFixtures

    private func logSets(_ result: ParseResult) -> [LogSetSpec] {
        result.commands.compactMap { if case .logSet(let spec) = $0 { return spec } else { return nil } }
    }

    @Test("225 for 8 and two twenty five for eight agree in an lb gym")
    func twoTwentyFive() {
        let context = Fixtures.benchContext(unit: .lb)
        for text in ["225 for 8", "two twenty five for eight"] {
            let spec = logSets(VoiceCommandParser.parse(text, context: context)).first
            #expect(spec?.sets.first?.reps == 8, "\(text)")
            #expect(abs((spec?.sets.first?.weightKg ?? 0) - 102.06) < 0.05, "\(text)")
        }
    }

    @Test("one twenty eight reps is 120 for 8, not 128")
    func oneTwentyEightReps() {
        let result = VoiceCommandParser.parse("one twenty eight reps", context: Fixtures.benchContext())
        let spec = logSets(result).first
        #expect(spec?.sets.first?.reps == 8)
        #expect(spec?.sets.first?.weightKg == 120)
    }

    @Test("three clauses log three exercises and a hundred and five does not split")
    func threeClauseCompound() {
        let result = VoiceCommandParser.parse(
            "bench a hundred and five for three and rows sixty for eight and curls ten at twenty",
            context: Fixtures.benchContext()
        )
        let specs = logSets(result)
        #expect(result.matchedPattern == "compound")
        #expect(specs.count == 3)
        #expect(specs.map(\.exercise) == [.id(Fixtures.benchID), .id(Fixtures.rowsID), .id(Fixtures.curlID)])
        #expect(specs.map { $0.sets.first?.weightKg } == [105, 60, 20])
        #expect(specs.map { $0.sets.first?.reps } == [3, 8, 10])
    }

    @Test("dictation punctuation and hyphenated number words")
    func punctuation() {
        let context = Fixtures.benchContext()
        #expect(VoiceCommandParser.parse("no, eight not nine", context: context).commands
            == [.correctLastSet(.init(reps: 8))])
        #expect(VoiceCommandParser.parse("actually that was ninety-five", context: context).commands
            == [.correctLastSet(.init(weightKg: 95))])
        let decimal = logSets(VoiceCommandParser.parse("102.5 for 3", context: context)).first
        #expect(decimal?.sets.first?.weightKg == 102.5)
    }

    @Test("typed shorthand: 5x5, 100kg, ×")
    func gluedShorthand() {
        let context = Fixtures.benchContext()
        let byForm = logSets(VoiceCommandParser.parse("5x5 at 100", context: context)).first
        #expect(byForm?.sets.count == 5)
        #expect(byForm?.sets.allSatisfy { $0.reps == 5 && $0.weightKg == 100 } == true)
        let glued = logSets(VoiceCommandParser.parse("100kg for 8", context: context)).first
        #expect(glued?.sets.first?.weightKg == 100)
        #expect(glued?.sets.first?.reps == 8)
        let times = logSets(VoiceCommandParser.parse("3 × 8 at 60", context: context)).first
        #expect(times?.sets.count == 3)
    }

    @Test("minus twenty five is 25 kg of assistance, with an optional unit word")
    func assistanceCompound() {
        let context = Fixtures.benchContext()
        let plain = logSets(VoiceCommandParser.parse(
            "assisted pull ups minus twenty five eight reps", context: context
        )).first
        #expect(plain?.sets.first?.assistanceKg == 25)
        #expect(plain?.sets.first?.reps == 8)
        #expect(plain?.sets.first?.weightKg == nil)
        let unit = logSets(VoiceCommandParser.parse(
            "assisted pull ups minus twenty kilos eight reps", context: context
        )).first
        #expect(unit?.sets.first?.assistanceKg == 20)
        #expect(unit?.exercise == .id(Fixtures.assistedPullUpID))
    }

    @Test("at a nine is an RPE; at ten is a weight")
    func atArticle() {
        let context = Fixtures.benchContext()
        let rated = logSets(VoiceCommandParser.parse("eight at a nine", context: context)).first
        #expect(rated?.effort == Effort(rpe: 9))
        #expect(rated?.sets.first?.reps == 8)
        let loaded = logSets(VoiceCommandParser.parse("curls ten at ten", context: context)).first
        #expect(loaded?.effort == nil)
        #expect(loaded?.sets.first?.weightKg == 10)
        #expect(loaded?.sets.first?.isBodyweight == false)
    }

    @Test("filler words never become the exercise")
    func fillers() {
        let context = Fixtures.benchContext()
        for text in ["just eight at a hundred", "ok eight at a hundred", "so eight reps"] {
            let spec = logSets(VoiceCommandParser.parse(text, context: context)).first
            #expect(spec?.exercise == nil, Comment(rawValue: text))
            #expect(spec?.sets.first?.isBodyweight == false, Comment(rawValue: text))
            #expect(spec?.sets.first?.reps == 8, Comment(rawValue: text))
        }
    }

    @Test("out-of-range effort is refused, not clamped")
    func effortOutOfRange() {
        let context = Fixtures.benchContext()
        for text in ["rpe three", "six in the tank"] {
            let result = VoiceCommandParser.parse(text, context: context)
            #expect(result.commands.isEmpty, Comment(rawValue: text))
            #expect(result.unresolved == [.effortOutOfRange], Comment(rawValue: text))
        }
    }

    @Test("a minute and a half in a hold and in a rest")
    func minuteAndAHalf() {
        let held = logSets(VoiceCommandParser.parse(
            "held the plank for a minute and a half", context: Fixtures.plankContext()
        )).first
        #expect(held?.sets.first?.durationSeconds == 90)
        let rest = VoiceCommandParser.parse("rest two minutes and a half", context: Fixtures.benchContext())
        #expect(rest.commands == [.rest(.start(seconds: 150))])
    }

    @Test("note wins over rest; got it completes; drop removes")
    func ordering() {
        let context = Fixtures.benchContext()
        #expect(VoiceCommandParser.parse("note rest felt short", context: context).commands
            == [.addNote(exercise: .onDeck, text: "rest felt short")])
        #expect(VoiceCommandParser.parse("got it", context: context).commands == [.completeOnDeck])
        #expect(VoiceCommandParser.parse("drop leg press", context: context).commands
            == [.removeExercise(.id(Fixtures.legPressID))])
        #expect(VoiceCommandParser.parse("drop five", context: context).commands
            == [.repeatPrevious(overrides: .init(weightDeltaKg: -5))])
    }

    @Test("what's my best bench asks about the on-deck exercise")
    func queryApostrophe() {
        let result = VoiceCommandParser.parse("what's my best bench", context: Fixtures.benchContext())
        #expect(result.commands == [.query(.personalRecord(.onDeck))])
    }

    @Test("a one-word shorthand does not auto-resolve to a same-prefix favourite")
    func benchIsNotBenchDips() {
        var context = Fixtures.benchContext()
        context.aliases = [:]
        let result = VoiceCommandParser.parse("bench eight at a hundred", context: context)
        let spec = logSets(result).first
        if case .spoken(_, let candidates) = spec?.exercise {
            #expect(candidates.contains { $0.id == Fixtures.benchID })
        } else {
            Issue.record("expected .spoken, got \(String(describing: spec?.exercise))")
        }
        #expect(result.confidence < 0.8)
        #expect(result.unresolved.contains(.exerciseAmbiguous))
    }

    @Test("a fuzzy match lowers confidence below auto-apply; an alias does not")
    func matchScoreInConfidence() {
        var context = Fixtures.benchContext()
        context.aliases = [:]
        let fuzzy = VoiceCommandParser.parse("incline dumbbell eight at thirty", context: context)
        #expect(logSets(fuzzy).first?.exercise == .id(Fixtures.inclineDumbbellPressID))
        #expect(fuzzy.confidence < 0.85)
        #expect(fuzzy.confidence >= 0.55)
        let alias = VoiceCommandParser.parse("bench eight at a hundred", context: Fixtures.benchContext())
        #expect(alias.confidence >= 0.9)
    }
}
