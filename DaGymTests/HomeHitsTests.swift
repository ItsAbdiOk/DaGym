import Testing

@testable import DaGym

/// The hero card's "HITS" lines, derived from `RoutineInfo.hitSummary`'s prose.
@Suite("Home hero hits lines")
struct HomeHitsTests {
    @Test("named muscles are dotted and title-cased, the light clause gets its own line")
    func namedAndLight() {
        let lines = HomeHits.lines(summary: "Chest, front delts, triceps · light on back")
        #expect(lines.named == "Chest · Front delts · Triceps")
        #expect(lines.light == "Light on back")
    }

    @Test("no light clause: one line only")
    func namedOnly() {
        let lines = HomeHits.lines(summary: "Lats, biceps")
        #expect(lines.named == "Lats · Biceps")
        #expect(lines.light == nil)
    }

    @Test("a routine that is only light on something keeps that as its one line")
    func lightOnly() {
        let lines = HomeHits.lines(summary: "Light on core and legs")
        #expect(lines.named == "Light on core and legs")
        #expect(lines.light == nil)
    }

    @Test("nothing yet passes through")
    func empty() {
        #expect(HomeHits.lines(summary: "Nothing yet").named == "Nothing yet")
    }
}
