import Foundation
import Testing
@testable import GymCore

@Suite("VoiceCommandParser matrix - part 2")
struct VoiceCommandParserTests2 {
    typealias Fixtures = VoiceCommandParserFixtures

    private func firstLogSet(_ result: ParseResult) -> LogSetSpec? {
        guard case .logSet(let spec) = result.commands.first else { return nil }
        return spec
    }

    // MARK: - Timed / Bodyweight / assisted / per-side

    @Test func row26_plankNinetySeconds() {
        let r = VoiceCommandParser.parse("plank ninety seconds", context: Fixtures.plankContext())
        #expect(r.confidence >= 0.9)
        #expect(firstLogSet(r)?.sets.first?.durationSeconds == 90)
    }

    @Test func row27_oneMinuteTwenty() {
        let r = VoiceCommandParser.parse("one minute twenty", context: Fixtures.plankContext())
        #expect(r.confidence >= 0.85)
        #expect(firstLogSet(r)?.sets.first?.durationSeconds == 80)
    }

    @Test func row28_twelvePullUps() {
        let r = VoiceCommandParser.parse("twelve pull ups", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.85)
        let spec = firstLogSet(r)
        #expect(spec?.sets.first?.reps == 12)
        #expect(spec?.sets.first?.isBodyweight == true)
    }

    @Test func row29_pullUpsWithTenKilosSixReps() {
        let r = VoiceCommandParser.parse(
            "pull ups with ten kilos six reps", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        let spec = firstLogSet(r)
        #expect(spec?.sets.first?.reps == 6)
        #expect(spec?.sets.first?.addedKg == 10)
    }

    @Test func row30_assistedPullUpsMinusTwentyEightReps() {
        let r = VoiceCommandParser.parse(
            "assisted pull ups minus twenty eight reps", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.8)
        let spec = firstLogSet(r)
        #expect(spec?.sets.first?.reps == 8)
        #expect(spec?.sets.first?.assistanceKg == 20)
    }

    @Test func row31_tenPerSideAtTwelve() {
        let r = VoiceCommandParser.parse("ten per side at twelve", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.85)
        let spec = firstLogSet(r)
        #expect(spec?.sets.first?.reps == 10)
        #expect(spec?.sets.first?.weightKg == 12)
        #expect(spec?.isPerSide == true)
    }

    @Test func row32_eightEachArmAtFourteen() {
        let r = VoiceCommandParser.parse(
            "eight each arm at fourteen", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        let spec = firstLogSet(r)
        #expect(spec?.sets.first?.reps == 8)
        #expect(spec?.sets.first?.weightKg == 14)
        #expect(spec?.isPerSide == true)
    }

    // MARK: - Swap / add / Kinds

    @Test func row33_swapThisForDumbbellPress() {
        let r = VoiceCommandParser.parse(
            "swap this for dumbbell press", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        #expect(r.commands == [.swapExercise(
            target: .onDeck, replacement: .id(Fixtures.dumbbellBenchID)
        )])
    }

    @Test func row34_switchBenchToInclineDumbbellPress() {
        let r = VoiceCommandParser.parse(
            "switch bench to incline dumbbell press", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        #expect(r.commands == [.swapExercise(
            target: .id(Fixtures.benchID),
            replacement: .id(Fixtures.inclineDumbbellPressID)
        )])
    }

    @Test func row35_addLateralRaises() {
        let r = VoiceCommandParser.parse("add lateral raises", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.85)
        #expect(r.commands == [.addExercise(.id(Fixtures.sideLateralRaiseID))])
    }

    @Test func row36_warmUpSetFortyForTen() {
        let r = VoiceCommandParser.parse(
            "warm up set forty for ten", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.9)
        let spec = firstLogSet(r)
        #expect(spec?.kind == .warmup)
        #expect(spec?.sets.first?.reps == 10)
        #expect(spec?.sets.first?.weightKg == 40)
    }

    @Test func row37_amrapAtAHundredGotEleven() {
        let r = VoiceCommandParser.parse(
            "amrap at a hundred got eleven", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        let spec = firstLogSet(r)
        #expect(spec?.kind == .amrap)
        #expect(spec?.sets.first?.reps == 11)
        #expect(spec?.sets.first?.weightKg == 100)
    }

    @Test func row38_dropSetSixtyForTen() {
        let r = VoiceCommandParser.parse(
            "drop set sixty for ten", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        let spec = firstLogSet(r)
        #expect(spec?.kind == .drop)
        #expect(spec?.sets.first?.reps == 10)
        #expect(spec?.sets.first?.weightKg == 60)
    }

    // MARK: - Compound / Rest / Note / Query

    @Test func row39_benchEightAtAHundredAndRowsEightAtSeventy() {
        let r = VoiceCommandParser.parse(
            "bench eight at a hundred and rows eight at seventy",
            context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.8)
        #expect(r.commands.count == 2)
        for command in r.commands {
            guard case .logSet(let spec) = command else {
                Issue.record("expected logSet"); continue
            }
            #expect(spec.sets.first?.reps == 8)
        }
    }

    @Test func row40_startTheRestTimer() {
        let r = VoiceCommandParser.parse(
            "start the rest timer", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.95)
        #expect(r.commands == [.rest(.start(seconds: nil))])
    }

    @Test func row41_restTwoMinutes() {
        let r = VoiceCommandParser.parse("rest two minutes", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.rest(.start(seconds: 120))])
    }

    @Test func row42_addThirtySeconds() {
        let r = VoiceCommandParser.parse("add thirty seconds", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.rest(.adjust(deltaSeconds: 30))])
    }

    @Test func row43_noteLeftShoulder() {
        let r = VoiceCommandParser.parse(
            "note left shoulder pinched on rep six", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.addNote(
            exercise: .onDeck, text: "left shoulder pinched on rep six"
        )])
    }

    @Test func row44_whatDidIDoLastTime() {
        let r = VoiceCommandParser.parse(
            "what did I do last time", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.query(.lastSession(.onDeck))])
    }

    @Test func row45_done() {
        let r = VoiceCommandParser.parse("done", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.9)
        #expect(r.commands == [.completeOnDeck])
    }

    // MARK: - Bare numbers / digit strings

    @Test func row46_eightAlone() {
        let r = VoiceCommandParser.parse("eight", context: Fixtures.benchContext())
        #expect(r.confidence >= 0.7)
        #expect(r.confidence < 0.8)
        #expect(firstLogSet(r)?.sets.first?.reps == 8)
    }

    @Test func row47_oneOhTwoPointFiveForThree() {
        let r = VoiceCommandParser.parse(
            "one oh two point five for three", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        #expect(firstLogSet(r)?.sets.first?.reps == 3)
        #expect(firstLogSet(r)?.sets.first?.weightKg == 102.5)
    }

    @Test func row48_hundredAndTwoAndAHalfKilosForThree() {
        let r = VoiceCommandParser.parse(
            "hundred and two and a half kilos for three", context: Fixtures.benchContext()
        )
        #expect(r.confidence >= 0.85)
        #expect(firstLogSet(r)?.sets.first?.reps == 3)
        #expect(firstLogSet(r)?.sets.first?.weightKg == 102.5)
    }

    @Test func row49_blahBlah() {
        let r = VoiceCommandParser.parse("blah blah", context: Fixtures.benchContext())
        #expect(r.commands.isEmpty)
        #expect(r.confidence == 0)
    }

    @Test func row50_sameAgainNoLastCompleted() {
        let r = VoiceCommandParser.parse(
            "same again", context: Fixtures.benchContext(lastCompleted: false)
        )
        #expect(r.commands == [.repeatPrevious(overrides: .init())])
        let validated = LogCommandValidator.validate(
            r.commands, in: Fixtures.benchContext(lastCompleted: false)
        )
        switch validated {
        case .failure(.nothingToRepeat): break
        default: Issue.record("expected .nothingToRepeat, got \(validated)")
        }
    }
}
