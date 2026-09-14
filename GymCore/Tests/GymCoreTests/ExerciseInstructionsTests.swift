import Testing

@testable import GymCore

/// Coverage for splitting a seeded exercise's inline-numbered instructions into steps for the
/// "How To Do It" card on Exercise Detail.
@Suite("Exercise instructions")
struct ExerciseInstructionsTests {
    @Test("numbered input splits into one step per marker")
    func numberedInputSplits() {
        let raw = """
            1. Sit in the machine with your chest against the pad and hands on the handles. \
            2. Pull the handles down by contracting your abs, bringing your ribs toward your hips. \
            3. Release slowly back to start.
            """

        let steps = ExerciseInstructions.steps(from: raw)

        #expect(steps.map(\.number) == [1, 2, 3])
        let first = "Sit in the machine with your chest against the pad and hands on the handles."
        #expect(steps[0].text == first)
        #expect(steps[1].text.hasPrefix("Pull the handles down"))
        #expect(steps[2].text == "Release slowly back to start.")
    }

    @Test("a trailing unnumbered sentence stays attached to the last step")
    func trailingSentenceStaysWithItsStep() {
        let raw = """
            1. Hold a kettlebell by the handle at waist height, hinging slightly at the hips. \
            2. Explosively extend your hips and knees, pulling the kettlebell upward and into the \
            rack position at your shoulder. 3. Lower back down and repeat on the opposite arm. \
            The power comes from your hips and hamstrings, not your arms.
            """

        let steps = ExerciseInstructions.steps(from: raw)

        #expect(steps.count == 3)
        #expect(steps[2].text.hasSuffix("The power comes from your hips and hamstrings, not your arms."))
        #expect(steps[2].text.hasPrefix("Lower back down and repeat on the opposite arm."))
    }

    @Test("prose comes back as a single unnumbered block, unchanged")
    func proseStaysProse() {
        let raw = """
            Lay down on a bench, the bar should be directly above your eyes, the knees are somewhat
            angled and the feet are firmly on the floor.
            """

        let steps = ExerciseInstructions.steps(from: raw)

        #expect(steps.count == 1)
        #expect(steps[0].number == nil)
        #expect(steps[0].text == raw)
    }

    @Test("an empty or whitespace-only string yields nothing")
    func emptyYieldsNothing() {
        #expect(ExerciseInstructions.steps(from: "").isEmpty)
        #expect(ExerciseInstructions.steps(from: "   \n  ").isEmpty)
    }

    @Test("a decimal inside a step never starts a new one")
    func decimalsAreNotMarkers() {
        let raw = "1. Load the bar with 2.5 kg a side. 2. Press it, adding 2.5 kg each week."

        let steps = ExerciseInstructions.steps(from: raw)

        #expect(steps.count == 2)
        #expect(steps[0].text == "Load the bar with 2.5 kg a side.")
        #expect(steps[1].text == "Press it, adding 2.5 kg each week.")
    }

    @Test("an out-of-sequence number stays inside its step")
    func outOfSequenceNumberIsNotAStep() {
        let raw = "1. Set up. 2. Hold for a count of 4. Then lower. 3. Repeat."

        let steps = ExerciseInstructions.steps(from: raw)

        #expect(steps.map(\.number) == [1, 2, 3])
        #expect(steps[1].text == "Hold for a count of 4. Then lower.")
    }

    @Test("text that is not numbered from the very start is left as prose")
    func listMustStartAtOne() {
        let raw = "Before you begin, warm up. 1. Set up. 2. Lift."

        let steps = ExerciseInstructions.steps(from: raw)

        #expect(steps.count == 1)
        #expect(steps[0].number == nil)
        #expect(steps[0].text == raw)
    }

    @Test("a lone numbered clause is not a list")
    func singleMarkerIsNotAList() {
        let steps = ExerciseInstructions.steps(from: "1. Just do the thing.")

        #expect(steps.count == 1)
        #expect(steps[0].number == nil)
        #expect(steps[0].text == "1. Just do the thing.")
    }

    @Test("steps split on a newline-separated list too")
    func newlineSeparatedMarkers() {
        let raw = "1. Set up.\n2. Lift.\n3. Lower."

        let steps = ExerciseInstructions.steps(from: raw)

        #expect(steps.map(\.number) == [1, 2, 3])
        #expect(steps.map(\.text) == ["Set up.", "Lift.", "Lower."])
    }
}
