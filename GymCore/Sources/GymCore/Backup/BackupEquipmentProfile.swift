import Foundation

/// One equipment profile as `BackupDocument.equipmentProfiles` carries it.
public struct BackupEquipmentProfile: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isActive: Bool
    public var barKg: Double
    public var availableEquipment: [String]
    /// The plate inventory as (weight, count) pairs — format 2. Read through
    /// `resolvedPlateStock`, which also understands the format-1 parallel arrays.
    public var plateStock: [BackupPlateStock]?
    /// Format 1: plate weights and counts as two parallel arrays. Still read; no longer
    /// written. Nothing guaranteed them the same length, so a hand-edited file could pair a
    /// plate with the wrong count — `resolvedPlateStock` zips them and drops the tail.
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
        availableEquipment: [String] = [], plateStock: [BackupPlateStock]? = nil,
        plateStockKg: [Double] = [], plateCounts: [Int] = [],
        collarsKg: Double = 0, createdAt: Date = Date(), seedKey: String? = nil,
        restrictsMachines: Bool? = nil, availableMachines: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.barKg = barKg
        self.availableEquipment = availableEquipment
        self.plateStock = plateStock
        self.plateStockKg = plateStockKg
        self.plateCounts = plateCounts
        self.collarsKg = collarsKg
        self.createdAt = createdAt
        self.seedKey = seedKey
        self.restrictsMachines = restrictsMachines
        self.availableMachines = availableMachines
    }

    /// The inventory as `PlateStock`, from the pairs or — for a format-1 file — the parallel
    /// arrays zipped, so a truncated array can't mis-pair a plate with another plate's count.
    public var resolvedPlateStock: [PlateStock] {
        if let plateStock {
            return plateStock.map { PlateStock(weightKg: $0.weightKg, count: $0.count) }
        }
        return zip(plateStockKg, plateCounts).map { PlateStock(weightKg: $0, count: $1) }
    }
}

/// One plate size and how many of it the gym has (format 2's `BackupEquipmentProfile.plateStock`).
public struct BackupPlateStock: Codable, Sendable, Hashable {
    public var weightKg: Double
    public var count: Int

    public init(weightKg: Double, count: Int) {
        self.weightKg = weightKg
        self.count = count
    }

    public init(_ stock: PlateStock) {
        self.init(weightKg: stock.weightKg, count: stock.count)
    }
}
