import Testing
@testable import GymCore

@Suite("WorkoutLayout")
struct WorkoutLayoutTests {
    @Test("a stored raw value wins over the legacy compact toggle")
    func storedValueWins() {
        #expect(WorkoutLayout(stored: "list", legacyCompact: true) == .list)
        #expect(WorkoutLayout(stored: "cards", legacyCompact: true) == .cards)
        #expect(WorkoutLayout(stored: "compact", legacyCompact: false) == .compact)
    }

    @Test("no stored value migrates the old compact toggle")
    func legacyToggleMigrates() {
        #expect(WorkoutLayout(stored: nil, legacyCompact: true) == .compact)
        #expect(WorkoutLayout(stored: nil, legacyCompact: false) == .cards)
    }

    @Test("an unknown raw value (a newer app's export) falls back like a missing one")
    func unknownValueFallsBack() {
        #expect(WorkoutLayout(stored: "grid", legacyCompact: false) == .cards)
        #expect(WorkoutLayout(stored: "grid", legacyCompact: true) == .compact)
        #expect(WorkoutLayout(stored: "", legacyCompact: false) == .cards)
    }

    @Test("only the cards layout keeps the on-deck extras")
    func extrasOnlyOnCards() {
        #expect(WorkoutLayout.cards.showsCardExtras)
        #expect(!WorkoutLayout.list.showsCardExtras)
        #expect(!WorkoutLayout.compact.showsCardExtras)
    }

    @Test("every case has a distinct title and symbol for the picker")
    func pickerRowsAreDistinct() {
        let titles = Set(WorkoutLayout.allCases.map(\.title))
        let symbols = Set(WorkoutLayout.allCases.map(\.symbolName))
        #expect(titles.count == WorkoutLayout.allCases.count)
        #expect(symbols.count == WorkoutLayout.allCases.count)
    }
}
