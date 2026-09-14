import Testing
@testable import GymCore

@Suite("Estimated 1RM")
struct OneRepMaxTests {
    @Test("100 kg × 5 by each formula")
    func formulas() throws {
        let epley = try #require(OneRepMax.estimate(weight: 100, reps: 5, formula: .epley))
        let brzycki = try #require(OneRepMax.estimate(weight: 100, reps: 5, formula: .brzycki))
        let wathen = try #require(OneRepMax.estimate(weight: 100, reps: 5, formula: .wathen))
        #expect(abs(epley - 116.667) < 0.01)
        #expect(abs(brzycki - 112.5) < 0.01)
        #expect(abs(wathen - 116.58) < 0.05)
    }

    @Test("e1RM is the mean of the three formulas")
    func mean() throws {
        let e1rm = try #require(OneRepMax.estimate(weight: 100, reps: 5))
        #expect(abs(e1rm - (116.667 + 112.5 + 116.58) / 3) < 0.05)
    }

    @Test("a single is its own max in every formula")
    func single() {
        for formula in OneRepMax.Formula.allCases {
            #expect(OneRepMax.estimate(weight: 140, reps: 1, formula: formula) == 140)
        }
    }

    @Test("sets over 12 reps, zero reps or zero weight are not eligible")
    func ineligible() {
        #expect(OneRepMax.estimate(weight: 60, reps: 13) == nil)
        #expect(OneRepMax.estimate(weight: 60, reps: 0) == nil)
        #expect(OneRepMax.estimate(weight: 0, reps: 5) == nil)
        #expect(OneRepMax.estimate(weight: 60, reps: 12) != nil)
    }

    @Test("reps in reserve count as extra reps to failure")
    func repsInReserve() throws {
        let hard = try #require(OneRepMax.estimate(weight: 100, reps: 5, repsInReserve: 0))
        let easy = try #require(OneRepMax.estimate(weight: 100, reps: 5, repsInReserve: 3))
        let sameAsEight = try #require(OneRepMax.estimate(weight: 100, reps: 8))
        #expect(easy > hard)
        #expect(easy == sameAsEight)
    }

    @Test("an RIR-extended rep count is clamped, never dropped off the eligible range")
    func repsInReserveClamps() throws {
        // 100 × 8 at RPE 5 is RIR 5 → 13 reps, which used to return nil: rating a set deleted
        // its e1RM from the progression rule while the same set left unrated still produced one.
        let rated = try #require(OneRepMax.estimate(weight: 100, reps: 8, repsInReserve: 5))
        let twelve = try #require(OneRepMax.estimate(weight: 100, reps: 12))
        let unrated = try #require(OneRepMax.estimate(weight: 100, reps: 8))
        #expect(rated == twelve)
        #expect(rated > unrated)
    }

    @Test("an RIR adjustment can't rescue a set that was ineligible on its own reps")
    func repsInReserveDoesNotRescueIneligibleSets() {
        #expect(OneRepMax.estimate(weight: 100, reps: 13, repsInReserve: 0) == nil)
        #expect(OneRepMax.estimate(weight: 0, reps: 5, repsInReserve: 2) == nil)
    }
}
