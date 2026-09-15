import Foundation
import SwiftData

/// A named equipment set the user trains with ("Gym", "Home"): bar weight,
/// plate inventory and what equipment kinds are available. CloudKit-legal:
/// no unique constraints, every stored property defaults. `plateStockKg` and
/// `plateCounts` are parallel arrays (index `i` is one plate size/count
/// pair) rather than a nested model, since SwiftData relationships add
/// CloudKit sync overhead this doesn't need.
@Model
final class EquipmentProfileModel {
    var id: UUID = UUID()
    var name: String = "Gym"
    var isActive: Bool = false
    var barKg: Double = 20
    /// Equipment kind strings: barbell, dumbbell, bodyweight, cable, machine,
    /// kettlebell, bands, ezBar, other.
    var availableEquipment: [String] = []
    /// Plate weight (kg) at index `i`, paired with `plateCounts[i]` — total
    /// plates in stock, not pairs (matches `GymCore.PlateStock.count`).
    var plateStockKg: [Double] = []
    var plateCounts: [Int] = []
    var collarsKg: Double = 0
    var createdAt: Date = Date()
    /// Stable identity for a profile `EquipmentSeeder` created ("gym"/"home"), `nil` for a
    /// profile the user made themselves. Lets `WorkoutStore.dedupeEquipmentProfiles()` fold two
    /// independently-seeded copies (two devices seeding before the first one's rows synced) back
    /// into one, the same way `ExerciseModel.seedID` does for exercises. Only a copy still
    /// holding the seeded values verbatim is ever folded away: once the user edits one, it is
    /// theirs and survives (see `SeededEquipmentProfile.isUntouchedSeededRow`).
    var seedKey: String?
    /// Whether `availableMachines` narrows the ticked kinds down to specific stations. False
    /// (the default every pre-existing row decodes to) means "every station of the ticked
    /// kinds" — what the app did before stations existed. True with an empty list is "none".
    var restrictsMachines: Bool = false
    /// `GymCore.Machine` raw values of the stations this gym has. Only read when
    /// `restrictsMachines` is true.
    var availableMachines: [String] = []

    init(
        id: UUID = UUID(), name: String = "Gym", isActive: Bool = false, barKg: Double = 20,
        availableEquipment: [String] = [], plateStockKg: [Double] = [], plateCounts: [Int] = [],
        collarsKg: Double = 0, createdAt: Date = Date(), seedKey: String? = nil,
        restrictsMachines: Bool = false, availableMachines: [String] = []
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.barKg = barKg
        self.availableEquipment = availableEquipment
        self.plateStockKg = plateStockKg
        self.plateCounts = plateCounts
        self.collarsKg = collarsKg
        self.createdAt = createdAt
        self.seedKey = seedKey
        self.restrictsMachines = restrictsMachines
        self.availableMachines = availableMachines
    }
}
