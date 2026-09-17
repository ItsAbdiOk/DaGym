import Testing

@testable import DaGym

@Suite("Routine tint suggestion")
struct RoutineTintSuggestionTests {
    @Test("Push / Pull / Legs get three different tints")
    func pushPullLegsDiffer() {
        let tints = ["Push A", "Pull B", "Legs"].map(RoutineTintSuggestion.tint(for:))
        #expect(Set(tints).count == 3)
        #expect(tints[0] == "coral")
    }

    @Test("Unknown names fall back to the accent")
    func unknownIsAccent() {
        #expect(RoutineTintSuggestion.tint(for: "Tuesday thing") == "coral")
    }
}
