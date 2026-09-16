import Foundation
import Testing

@testable import GymCore

@Suite("LibraryFacets")
struct LibraryFacetsTests {
    private let rows = [
        LibraryFacets.Entry(primary: [.chest], secondary: [.triceps, .delts], equipment: "barbell"),
        LibraryFacets.Entry(primary: [.chest], secondary: [.triceps], equipment: "dumbbell"),
        LibraryFacets.Entry(primary: [.quads], secondary: [.glutes], equipment: "barbell"),
        LibraryFacets.Entry(primary: [.lats, .biceps], secondary: [], equipment: "bodyweight")
    ]

    @Test("no selection: every muscle and equipment with a row is live, counted once per row")
    func nothingSelected() {
        let facets = LibraryFacets.remaining(rows, selectedMuscle: nil, selectedEquipment: nil)
        #expect(facets.muscleCounts[.chest] == 2)
        #expect(facets.muscleCounts[.triceps] == 2)
        #expect(facets.muscleCounts[.glutes] == 1)
        #expect(facets.muscleCounts[.calves] == nil)
        #expect(facets.equipmentCounts == ["barbell": 2, "dumbbell": 1, "bodyweight": 1])
        #expect(facets.muscles.contains(.lats))
        #expect(!facets.equipment.contains("machine"))
    }

    @Test("a selected equipment narrows the muscle chips; a selected muscle narrows equipment")
    func crossFilters() {
        let facets = LibraryFacets.remaining(rows, selectedMuscle: .chest, selectedEquipment: "barbell")
        // Muscles under barbell: chest row + quads row.
        #expect(facets.muscles == [.chest, .triceps, .delts, .quads, .glutes])
        // Equipment under chest: the two presses, never the bodyweight row.
        #expect(facets.equipment == ["barbell", "dumbbell"])
        #expect(facets.equipmentCounts["bodyweight"] == nil)
    }

    @Test("includeSecondary off drops the secondary-only muscles and their equipment matches")
    func primaryOnly() {
        let facets = LibraryFacets.remaining(
            rows, selectedMuscle: .triceps, selectedEquipment: nil, includeSecondary: false
        )
        #expect(facets.muscleCounts[.triceps] == nil)
        #expect(facets.muscleCounts[.chest] == 2)
        #expect(facets.equipment.isEmpty)
    }

    @Test("a selected chip that no longer matches anything simply has no count")
    func selectedButEmpty() {
        let facets = LibraryFacets.remaining(rows, selectedMuscle: .calves, selectedEquipment: "machine")
        #expect(facets.muscleCounts.isEmpty)
        #expect(facets.equipmentCounts.isEmpty)
    }

    @Test("empty library yields empty facets")
    func emptyLibrary() {
        let facets = LibraryFacets.remaining([], selectedMuscle: nil, selectedEquipment: nil)
        #expect(facets == LibraryFacets.Remaining())
    }

    @Test("map intensity: the top muscle is 1, one row is still lit, zero and absent are inert")
    func mapIntensity() {
        let map = LibraryFacets.mapIntensity(counts: [.chest: 100, .calves: 1, .abs: 0])
        #expect(map[.chest] == 1)
        #expect(map[.calves].map { $0 >= LibraryFacets.minimumLit && $0 < 0.5 } == true)
        #expect(map[.abs] == nil)
        #expect(map[.lats] == nil)
        #expect(LibraryFacets.mapIntensity(counts: [:]).isEmpty)
        #expect(LibraryFacets.mapIntensity(counts: [.abs: 0]).isEmpty)
    }

    @Test("a muscle listed as both primary and secondary of one row counts that row once")
    func duplicateMuscleInOneRow() {
        let row = LibraryFacets.Entry(primary: [.abs], secondary: [.abs, .obliques], equipment: "other")
        let facets = LibraryFacets.remaining([row], selectedMuscle: nil, selectedEquipment: nil)
        #expect(facets.muscleCounts[.abs] == 1)
    }
}
