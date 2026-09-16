import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// `WorkoutStore.libraryFacets` — the chips the library dims — over real rows: the seeded
/// library, an equipment profile that hides machines, favourites-only, and "show all".
@MainActor
@Suite("Library facets over the store")
struct LibraryFacetsStoreTests {
    @discardableResult
    private func exercise(
        _ store: WorkoutStore, _ name: String, primary: Muscle, secondary: [Muscle] = [],
        equipment: String, machine: String? = nil
    ) -> ExerciseInfo {
        let info = store.createCustomExercise(
            name: name, primary: [primary], equipment: equipment, style: .weightReps, machine: machine
        )
        guard !secondary.isEmpty, let model = store.fetchExerciseModel(id: info.id) else { return info }
        model.secondaryMuscles = secondary.map(\.rawValue)
        store.save()
        return info
    }

    private func facets(
        _ store: WorkoutStore, query: String = "", favoritesOnly: Bool = false,
        availability: EquipmentAvailability? = nil, muscle: Muscle? = nil, equipment: String? = nil,
        includeSecondary: Bool = true
    ) -> LibraryFacets.Remaining {
        store.libraryFacets(
            in: store.exerciseCatalogue(), matching: query, favoritesOnly: favoritesOnly, customOnly: false,
            availability: availability, selectedMuscle: muscle, selectedEquipment: equipment,
            includeSecondary: includeSecondary
        )
    }

    @Test("empty store: nothing is live")
    func emptyStore() throws {
        let store = try makeStore()
        #expect(facets(store) == LibraryFacets.Remaining())
    }

    @Test("the seeded library lights every muscle and every equipment kind the seed uses")
    func seededLibrary() throws {
        let store = try makeStore(seed: .exercises)
        let all = facets(store)
        #expect(all.muscles == Set(Muscle.allCases))
        #expect(all.equipment.isSuperset(of: ["barbell", "dumbbell", "bodyweight", "cable", "machine"]))
        // Search text narrows both rows: "pull-up" is a lats/biceps bodyweight movement.
        let pullUps = facets(store, query: "pull-up")
        #expect(pullUps.muscles.contains(.lats))
        #expect(!pullUps.muscles.contains(.calves))
        #expect(pullUps.equipment.contains("bodyweight"))
    }

    @Test("a profile with machines restricted drops the muscles only a missing station trains")
    func machineRestrictedProfile() throws {
        let store = try makeStore()
        exercise(store, "Pec Deck", primary: .chest, equipment: "machine", machine: "pecDeck")
        exercise(
            store, "Leg Press", primary: .quads, secondary: [.glutes], equipment: "machine",
            machine: "legPress"
        )
        exercise(store, "Squat", primary: .quads, equipment: "barbell")
        let gym = EquipmentAvailability(
            types: ["barbell", "machine"], restrictsMachines: true, machines: [.legPress]
        )
        let facets = facets(store, availability: gym)
        #expect(facets.muscles == [.quads, .glutes])
        #expect(facets.equipment == ["machine", "barbell"])
        #expect(facets.equipmentCounts["machine"] == 1)
        // "Show all" hands nil availability and the pec deck comes back.
        #expect(self.facets(store).muscles.contains(.chest))
    }

    @Test("favourites-only counts favourites alone; a selected empty chip has no count")
    func favouritesOnly() throws {
        let store = try makeStore()
        let row = exercise(store, "Row", primary: .lats, equipment: "cable")
        exercise(store, "Curl", primary: .biceps, equipment: "dumbbell")
        store.toggleFavorite(id: row.id)
        let favourites = facets(store, favoritesOnly: true)
        #expect(favourites.muscles == [.lats])
        #expect(favourites.equipment == ["cable"])
        // Biceps selected while favourites-only: nothing matches, so the chip reads empty.
        let stuck = facets(store, favoritesOnly: true, muscle: .biceps)
        #expect(!stuck.muscles.contains(.biceps))
        #expect(stuck.equipment.isEmpty)
    }

    @Test("includeSecondary off: a secondary-only muscle stops matching in the list and the chips")
    func primaryOnlyMatchesTheList() throws {
        let store = try makeStore()
        exercise(store, "Leg Press", primary: .quads, secondary: [.glutes], equipment: "machine")
        let catalogue = store.exerciseCatalogue()
        #expect(store.exercises(in: catalogue, muscle: .glutes).count == 1)
        #expect(store.exercises(in: catalogue, muscle: .glutes, includeSecondary: false).isEmpty)
        #expect(facets(store, includeSecondary: false).muscles == [.quads])
    }
}
