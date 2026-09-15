import Foundation

/// One equipment profile as `BackupDocument.equipmentProfiles` carries it.
public struct BackupEquipmentProfile: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isActive: Bool
    public var barKg: Double
    public var availableEquipment: [String]
    public var plateStockKg: [Double]
    public var plateCounts: [Int]
    public var collarsKg: Double
    public var createdAt: Date
    /// `EquipmentProfileModel.seedKey` — "gym"/"home" for a seeded profile, `nil` for one the
    /// user made. Carried through a backup so a restored profile keeps its seed identity
    /// instead of arriving unkeyed and being re-derived by a guess on the restoring device.
    /// Absent from backups written before this field existed, which decode as `nil`.
    public var seedKey: String?
    /// `EquipmentProfileModel.restrictsMachines` / `availableMachines`: whether the profile
    /// narrows its ticked kinds down to specific stations, and which (`Machine` raw values).
    /// Absent from older backups, which decode as "every station" — what they meant.
    public var restrictsMachines: Bool?
    public var availableMachines: [String]?

    public init(
        id: UUID, name: String, isActive: Bool = false, barKg: Double = 20,
        availableEquipment: [String] = [], plateStockKg: [Double] = [], plateCounts: [Int] = [],
        collarsKg: Double = 0, createdAt: Date = Date(), seedKey: String? = nil,
        restrictsMachines: Bool? = nil, availableMachines: [String]? = nil
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
