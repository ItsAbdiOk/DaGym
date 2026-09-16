import Foundation
import GymCore

extension WorkoutStore {
    /// Which of the library's chips would still find a row — `LibraryFacets.remaining` over the
    /// rows the search text, the favourites/custom toggles and the equipment profile let
    /// through. One unsorted pass over the cached catalogue, no `ExerciseInfo` mapping, so it
    /// costs a fraction of the row filter it runs beside; `availability` nil means the profile
    /// hides nothing (or "show all" is on).
    func libraryFacets(
        in catalogue: ExerciseCatalogue, matching query: String = "", favoritesOnly: Bool = false,
        customOnly: Bool = false, availability: EquipmentAvailability? = nil, selectedMuscle: Muscle? = nil,
        selectedEquipment: String? = nil, includeSecondary: Bool = true
    ) -> LibraryFacets.Remaining {
        let models = exerciseModels(
            in: catalogue, matching: query, favoritesOnly: favoritesOnly, customOnly: customOnly
        )
        let allowed = models.lazy.filter {
            availability?.allows(equipment: $0.equipment, machine: $0.machine) ?? true
        }
        let entries = allowed.map {
            LibraryFacets.Entry(primary: $0.primary, secondary: $0.secondary, equipment: $0.equipment)
        }
        return LibraryFacets.remaining(
            entries, selectedMuscle: selectedMuscle, selectedEquipment: selectedEquipment,
            includeSecondary: includeSecondary
        )
    }
}
