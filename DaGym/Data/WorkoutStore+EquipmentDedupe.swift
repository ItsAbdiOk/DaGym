import Foundation
import GymCore
import SwiftData

/// The two profiles `EquipmentSeeder` creates, and — crucially — exactly what it writes into
/// them. Keeping the seeded values here (rather than inline in the seeder) is what lets the
/// dedupe pass tell an *untouched seeded* row apart from a row the user made or edited that
/// merely shares its name.
enum SeededEquipmentProfile: String, CaseIterable {
    case gym
    case home

    /// The `seedKey` stored on `EquipmentProfileModel`.
    var key: String { rawValue }

    var name: String {
        switch self {
        case .gym: "Gym"
        case .home: "Home"
        }
    }

    var isActiveWhenSeeded: Bool { self == .gym }

    /// The bar, in the unit the lifter picked during onboarding: a 20 kg Olympic bar, or the
    /// 45 lb bar every American rack actually holds. Seeding kg regardless of the choice is
    /// what put lb lifters on kg-loadable prescriptions ("137.8 lb") no gym can build.
    func barKg(for unit: WeightUnit) -> Double { unit.defaultBar.weightKg }

    var availableEquipment: [String] {
        switch self {
        case .gym: EquipmentOption.allCases.map(\.rawValue)
        case .home: ["dumbbell", "bodyweight", "bands"]
        }
    }

    /// The plate inventory, in the lifter's own unit (`WeightUnit.plateStock`).
    func plateStock(for unit: WeightUnit) -> [PlateStock] {
        switch self {
        case .gym: WeightUnit.plateStock(for: unit)
        case .home: []
        }
    }

    var collarsKg: Double { 0 }

    static func named(_ name: String) -> SeededEquipmentProfile? {
        allCases.first { $0.name == name }
    }

    /// True only when `model` still holds exactly what the seeder wrote — same name, bar, kit
    /// list, plates and collars. The moment the user changes any of that (or creates their own
    /// profile that happens to be called "Gym"), this is false and the row is treated as the
    /// user's, never as a seeded duplicate.
    /// Checked against *both* units' seed values: a row seeded in lb is just as untouched as
    /// one seeded in kg, and the lifter may have switched units since.
    func isUntouchedSeededRow(_ model: EquipmentProfileModel) -> Bool {
        WeightUnit.allCases.contains { isUntouchedSeededRow(model, unit: $0) }
    }

    private func isUntouchedSeededRow(_ model: EquipmentProfileModel, unit: WeightUnit) -> Bool {
        let stock = plateStock(for: unit)
        return model.name == name
            && model.barKg == barKg(for: unit)
            && model.availableEquipment == availableEquipment
            && model.plateStockKg == stock.map(\.weightKg)
            && model.plateCounts == stock.map(\.count)
            && model.collarsKg == collarsKg
    }
}

extension WorkoutStore {
    /// Folds duplicate equipment profiles two devices can each produce by seeding "Gym"/"Home"
    /// before the other's rows synced down — the same class of race `ExerciseSeeder.dedupe(in:)`
    /// handles for exercises. Seeded profiles fold on `seedKey`; rows predating `seedKey` get it
    /// backfilled first, but *only* when they still hold the seeded values exactly, so a profile
    /// the user made or edited is never mistaken for a seeded one on the strength of its name.
    /// Anything left over — genuinely custom, unkeyed profiles — still folds if every field
    /// matches, the original safety net. Nothing the user has edited is ever deleted. Finally, a
    /// fold can leave two rows active (each group carried its own active flag), so exactly one is
    /// kept active at the end. Returns the number removed.
    @discardableResult
    func dedupeEquipmentProfiles() -> Int {
        let models = fetch(FetchDescriptor<EquipmentProfileModel>())
        backfillLegacyEquipmentSeedKeys(models)
        var removed = foldSeededEquipmentProfiles(models)
        removed += foldEquipmentProfiles(groupedByFieldsEquality: models.filter { $0.seedKey == nil })
        let reactivated = normaliseActiveEquipmentProfile()
        if removed > 0 || reactivated { save() }
        return removed
    }

    /// A profile seeded before `seedKey` existed has none; match it back to its seed identity so
    /// it folds with any newer, correctly-keyed copy instead of surviving as an orphan.
    ///
    /// Name alone is not enough evidence: "Gym" and "Home" are the two names a user is most
    /// likely to pick themselves, and stamping a user's own "Gym" with `seedKey == "gym"` used to
    /// hand it to the fold, which kept the older seeded row and deleted theirs — silent,
    /// unrecoverable data loss that repeated every launch. So the row must also still hold every
    /// value the seeder wrote.
    private func backfillLegacyEquipmentSeedKeys(_ models: [EquipmentProfileModel]) {
        for model in models where model.seedKey == nil {
            guard let seed = SeededEquipmentProfile.named(model.name),
                  seed.isUntouchedSeededRow(model)
            else { continue }
            model.seedKey = seed.key
        }
    }

    /// Folds rows sharing a `seedKey`. The survivor is the one the user has edited, if any
    /// (their work outranks a pristine copy from another device), else the oldest; only rows
    /// that are still untouched seed defaults are deleted. Two rows both edited differently are
    /// both kept — there is no safe way to merge them, so neither is thrown away.
    private func foldSeededEquipmentProfiles(_ models: [EquipmentProfileModel]) -> Int {
        var removed = 0
        for seed in SeededEquipmentProfile.allCases {
            let group = models.filter { $0.seedKey == seed.key }.sorted(by: Self.olderFirst)
            guard group.count > 1 else { continue }
            let survivor = group.first { !seed.isUntouchedSeededRow($0) } ?? group[0]
            for duplicate in group where duplicate !== survivor {
                guard seed.isUntouchedSeededRow(duplicate) else { continue }
                survivor.isActive = survivor.isActive || duplicate.isActive
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    private func foldEquipmentProfiles(groupedByFieldsEquality models: [EquipmentProfileModel]) -> Int {
        var groups: [String: [EquipmentProfileModel]] = [:]
        for model in models {
            let key = [
                model.name, "\(model.barKg)", model.availableEquipment.joined(separator: ","),
                model.plateStockKg.map { "\($0)" }.joined(separator: ","),
                model.plateCounts.map { "\($0)" }.joined(separator: ","), "\(model.collarsKg)"
            ].joined(separator: "|")
            groups[key, default: []].append(model)
        }
        var removed = 0
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted(by: Self.olderFirst)
            for duplicate in ordered.dropFirst() {
                ordered[0].isActive = ordered[0].isActive || duplicate.isActive
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    /// Leaves exactly one profile active. Folding two groups can leave both "Gym" and "Home"
    /// active (each inherited an active flag from its own duplicate), which `activeProfile()`
    /// resolves silently by picking the older while Settings draws two checkmarks. The oldest
    /// active row wins. Returns whether anything changed.
    @discardableResult
    func normaliseActiveEquipmentProfile() -> Bool {
        let active = fetch(FetchDescriptor<EquipmentProfileModel>())
            .filter(\.isActive)
            .sorted(by: Self.olderFirst)
        guard active.count > 1 else { return false }
        for model in active.dropFirst() { model.isActive = false }
        return true
    }

    /// Deterministic ordering for survivor selection: oldest first, `id` breaking a tie.
    private static func olderFirst(_ lhs: EquipmentProfileModel, _ rhs: EquipmentProfileModel) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
