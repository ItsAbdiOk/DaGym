// swiftlint:disable large_tuple
import Foundation
import Testing
@testable import GymCore

@Suite("Routine muscles")
struct RoutineMusclesTests {
    private typealias Entry = (primary: [Muscle], secondary: [Muscle], setCount: Int)

    @Test("empty exercise list yields an empty hit map")
    func emptyHitMap() {
        let hit = RoutineMuscles.hitMap(exercises: [])
        #expect(hit.isEmpty)
    }

    @Test("hit map normalises so the most-worked muscle is 1.0")
    func normalisation() {
        let exercises: [Entry] = [
            (primary: [.chest], secondary: [], setCount: 4),
            (primary: [.quads], secondary: [], setCount: 2)
        ]
        let hit = RoutineMuscles.hitMap(exercises: exercises)
        #expect(hit[.chest] == 1.0)
        #expect(hit[.quads] == 0.5)
    }

    @Test("secondary muscles count at the shared secondary share")
    func secondaryHalfWeight() {
        let exercises: [Entry] = [
            (primary: [.chest], secondary: [.triceps], setCount: 4)
        ]
        let hit = RoutineMuscles.hitMap(exercises: exercises)
        #expect(hit[.chest] == 1.0)
        #expect(hit[.triceps] == SessionStats.secondaryMuscleShare)
    }

    @Test("set count weights each exercise's contribution")
    func setCountWeighting() {
        let exercises: [Entry] = [
            (primary: [.chest], secondary: [], setCount: 3),
            (primary: [.triceps], secondary: [], setCount: 1)
        ]
        let hit = RoutineMuscles.hitMap(exercises: exercises)
        #expect(hit[.chest] == 1.0)
        #expect(abs((hit[.triceps] ?? 0) - (1.0 / 3.0)) < 0.0001)
    }

    @Test("summary names muscles at or above 0.6, first capitalised, rest lowercase")
    func summaryNamesHighMuscles() {
        let hit: [Muscle: Double] = [.chest: 1.0, .delts: 0.8, .triceps: 0.65]
        let summary = RoutineMuscles.summary(hitMap: hit)
        #expect(summary.hasPrefix("Chest, delts, triceps"))
    }

    @Test("summary folds 0.2..<0.6 muscles into a light-on clause")
    func summaryLightClause() {
        let hit: [Muscle: Double] = [.chest: 1.0, .delts: 0.8, .triceps: 0.65, .lowerBack: 0.3]
        let summary = RoutineMuscles.summary(hitMap: hit)
        #expect(summary == "Chest, delts, triceps · light on back")
    }

    @Test("summary omits muscles worked below 0.2")
    func summaryDropsBelowThreshold() {
        let hit: [Muscle: Double] = [.chest: 1.0, .calves: 0.05]
        let summary = RoutineMuscles.summary(hitMap: hit)
        #expect(summary == "Chest")
    }

    @Test("empty hit map summarises as Nothing yet")
    func summaryEmpty() {
        #expect(RoutineMuscles.summary(hitMap: [:]) == "Nothing yet")
    }
}
// swiftlint:enable large_tuple
