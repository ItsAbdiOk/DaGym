import Foundation
import Testing
@testable import GymCore

/// The §4.9 test matrix: 50 utterances against a fixed context (unit kg,
/// on-deck = Barbell Bench Press 100 × 8, last completed 100 × 8, bar 20 kg;
/// timed rows use Plank).

enum VoiceCommandParserFixtures {
    static let benchID = UUID()
    static let plankID = UUID()
    static let rowsID = UUID()
    static let dumbbellBenchID = UUID()
    static let inclineDumbbellBenchID = UUID()
    static let sideLateralRaiseID = UUID()
    static let pullUpsID = UUID()
    static let assistedPullUpID = UUID()

    static func library() -> [ParseContext.ExerciseCandidate] {
        [
            ParseContext.ExerciseCandidate(
                id: benchID, name: "Barbell Bench Press", equipment: "barbell", isInSession: true
            ),
            ParseContext.ExerciseCandidate(id: plankID, name: "Plank"),
            ParseContext.ExerciseCandidate(
                id: rowsID, name: "Bent Over Barbell Row", equipment: "barbell", isInSession: true
            ),
            ParseContext.ExerciseCandidate(
                id: dumbbellBenchID, name: "Dumbbell Bench Press", equipment: "dumbbell"
            ),
            ParseContext.ExerciseCandidate(
                id: inclineDumbbellBenchID, name: "Incline Dumbbell Bench Press",
                equipment: "dumbbell"
            ),
            ParseContext.ExerciseCandidate(
                id: sideLateralRaiseID, name: "Side Lateral Raise", equipment: "dumbbell"
            ),
            ParseContext.ExerciseCandidate(id: pullUpsID, name: "Pull-Ups"),
            ParseContext.ExerciseCandidate(id: assistedPullUpID, name: "Assisted Pull-Up")
        ]
    }

    static func aliases() -> [String: UUID] {
        [
            "bench": benchID, "rows": rowsID, "dumbbell press": dumbbellBenchID,
            "lateral raises": sideLateralRaiseID
        ]
    }

    /// unit kg; on-deck = Barbell Bench Press working set prefilled 100 × 8;
    /// last completed = 100 × 8 (no effort); bar 20 kg.
    static func benchContext(unit: WeightUnit = .kg, lastCompleted: Bool = true) -> ParseContext {
        ParseContext(
            unit: unit,
            onDeck: ParseContext.OnDeckSet(
                exerciseID: benchID, name: "Barbell Bench Press", loggingStyle: .weightReps,
                prefilledWeightKg: 100, prefilledReps: 8
            ),
            lastCompleted: lastCompleted
                ? ParseContext.CompletedSetRef(
                    exerciseID: benchID, setID: UUID(), weightKg: 100, reps: 8
                )
                : nil,
            sessionExercises: library().filter(\.isInSession),
            library: library(),
            aliases: aliases()
        )
    }

    /// Timed rows: on-deck is Plank.
    static func plankContext() -> ParseContext {
        ParseContext(
            unit: .kg,
            onDeck: ParseContext.OnDeckSet(
                exerciseID: plankID, name: "Plank", loggingStyle: .timedHold
            ),
            lastCompleted: ParseContext.CompletedSetRef(
                exerciseID: plankID, setID: UUID(), durationSeconds: 45
            ),
            sessionExercises: [ParseContext.ExerciseCandidate(
                id: plankID, name: "Plank", isInSession: true
            )],
            library: library(),
            aliases: aliases()
        )
    }
}

@Suite("VoiceCommandParser matrix - part 1")
struct VoiceCommandParserTests1 {
    typealias Fixtures = VoiceCommandParserFixtures

    private func firstLogSet(_ result: ParseResult) -> LogSetSpec? {
        guard case .logSet(let spec) = result.commands.first else { return nil }
        return spec
    }

    // MARK: - Reps/weight rows

    @Test func row1_didEightAtAHundred() {
        let r = VoiceCommandParser.parse("did eight at a hundred", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(firstLogSet(r)?.sets.first?.reps == 8)
        #expect(firstLogSet(r)?.sets.first?.weightKg == 100)
    }

    @Test func row2_eightAtAHundredFeltLikeAnEight() {
        let r = VoiceCommandParser.parse(
            "eight at a hundred felt like an eight", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.9)
        let spec = firstLogSet(r)
        #expect(spec?.sets.first?.reps == 8)
        #expect(spec?.sets.first?.weightKg == 100)
        #expect(spec?.effort?.rpe == 8)
    }

    @Test func row3_oneHundredKilosForEightReps() {
        let r = VoiceCommandParser.parse(
            "one hundred kilos for eight reps", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.9)
        #expect(firstLogSet(r)?.sets.first?.reps == 8)
        #expect(firstLogSet(r)?.sets.first?.weightKg == 100)
    }

    @Test func row4_eightRepsAt225Pounds() {
        let r = VoiceCommandParser.parse("8 reps at 225 pounds", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(firstLogSet(r)?.sets.first?.reps == 8)
        #expect(abs((firstLogSet(r)?.sets.first?.weightKg ?? 0) - 102.06) < 0.05)
    }

    @Test func row5_eightAt225UnitLb() {
        let r = VoiceCommandParser.parse("8 at 225", context: Fixtures.benchContext(unit: .lb))
        #expect(r.confidence >= 0.9)
        #expect(firstLogSet(r)?.sets.first?.reps == 8)
        #expect(abs((firstLogSet(r)?.sets.first?.weightKg ?? 0) - 102.06) < 0.05)
    }

    @Test func row6_twoPlatesForFive() {
        let r = VoiceCommandParser.parse("two plates for five", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.85)
        #expect(firstLogSet(r)?.sets.first?.reps == 5)
        #expect(firstLogSet(r)?.sets.first?.weightKg == 100)
    }

    @Test func row7_aPlateAndAHalfForEight() {
        let r = VoiceCommandParser.parse(
            "a plate and a half for eight", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.8)
        #expect(firstLogSet(r)?.sets.first?.reps == 8)
        #expect(firstLogSet(r)?.sets.first?.weightKg == 80)
    }

    // MARK: - Repeat

    @Test func row8_sameAgain() {
        let r = VoiceCommandParser.parse("same again", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.repeatPrevious(overrides: .init())])
    }

    @Test func row9_sameAgainButSevenReps() {
        let r = VoiceCommandParser.parse(
            "same again but seven reps", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.repeatPrevious(overrides: .init(reps: 7))])
    }

    @Test func row10_sameWeightNine() {
        let r = VoiceCommandParser.parse("same weight nine", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.85)
        #expect(r.commands == [.repeatPrevious(overrides: .init(reps: 9))])
    }

    @Test func row11_addTwoAndAHalfAndDoEight() {
        let r = VoiceCommandParser.parse(
            "add two and a half and do eight", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        guard case .repeatPrevious(let overrides) = r.commands.first else {
            Issue.record("expected repeatPrevious"); return
        }
        #expect(overrides.reps == 8)
        #expect(overrides.weightDeltaKg == 2.5)
    }

    @Test func row12_dropToNinetyTwelveReps() {
        let r = VoiceCommandParser.parse(
            "drop to ninety twelve reps", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        #expect(firstLogSet(r)?.sets.first?.reps == 12)
        #expect(firstLogSet(r)?.sets.first?.weightKg == 90)
    }

    // MARK: - Effort

    @Test func row13_thatFeltLikeANine() {
        let r = VoiceCommandParser.parse("that felt like a nine", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.rateLastSet(Effort(rpe: 9))])
    }

    @Test func row14_rpeEightAndAHalf() {
        let r = VoiceCommandParser.parse("rpe eight and a half", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.rateLastSet(Effort(rpe: 8.5))])
    }

    @Test func row15_twoInTheTank() {
        let r = VoiceCommandParser.parse("two in the tank", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.rateLastSet(Effort(rir: 2))])
    }

    @Test func row16_thatWasAGrind() {
        let r = VoiceCommandParser.parse("that was a grind", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.8)
        #expect(r.commands == [.rateLastSet(Effort(rpe: 10))])
    }

    // MARK: - Multi-set

    @Test func row17_threeSetsOfEightAtSixty() {
        let r = VoiceCommandParser.parse(
            "three sets of eight at sixty", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.88)
        let spec = firstLogSet(r)
        #expect(spec?.sets.count == 3)
        #expect(spec?.sets.allSatisfy { $0.reps == 8 && $0.weightKg == 60 } == true)
    }

    @Test func row18_fiveByFiveAtOneTwenty() {
        let r = VoiceCommandParser.parse(
            "five by five at one twenty", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.88)
        let spec = firstLogSet(r)
        #expect(spec?.sets.count == 5)
        #expect(spec?.sets.allSatisfy { $0.reps == 5 && $0.weightKg == 120 } == true)
    }

    @Test func row19_tenTenEightAtEighty() {
        let r = VoiceCommandParser.parse(
            "ten ten eight at eighty", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        let spec = firstLogSet(r)
        #expect(spec?.sets.map(\.reps) == [10, 10, 8])
        #expect(spec?.sets.allSatisfy { $0.weightKg == 80 } == true)
    }

    @Test func row20_threeSetsOfDumbbellRaisesAt5Kg() {
        let r = VoiceCommandParser.parse(
            "3 sets of dumbbell raises at 5 kg", context: Fixtures.benchContext()
        )
        let spec = firstLogSet(r)
        #expect(spec?.sets.count == 3)
        #expect(spec?.sets.allSatisfy { $0.weightKg == 5 && $0.reps == nil } == true)
        #expect(r.unresolved.contains(.missingReps))
    }

    // MARK: - Correction / meta

    @Test func row21_noEightNotNine() {
        let r = VoiceCommandParser.parse("no eight not nine", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.correctLastSet(.init(reps: 8))])
    }

    @Test func row22_actuallyThatWasNinetyFive() {
        let r = VoiceCommandParser.parse(
            "actually that was ninety five", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        #expect(r.commands == [.correctLastSet(.init(weightKg: 95))])
    }

    @Test func row23_undo() {
        let r = VoiceCommandParser.parse("undo", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.95)
        #expect(r.commands == [.undo])
    }

    @Test func row24_scrapThat() {
        let r = VoiceCommandParser.parse("scrap that", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.undo])
    }

    // MARK: - Timed

    @Test func row25_heldThePlankForAMinute() {
        let r = VoiceCommandParser.parse(
            "held the plank for a minute", context: Fixtures.plankContext()
        )
        #expect(r.confidence >= 0.9)
        #expect(firstLogSet(r)?.sets.first?.durationSeconds == 60)
    }
}
