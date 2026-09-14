import Foundation
import GymCore
import SwiftData

/// One equipment set the user trains with ("Gym", "Home"), mapped from
/// `EquipmentProfileModel`. Plate inventory is exposed as `GymCore.PlateStock`
/// so it plugs straight into `PlateCalculator.load(target:bar:plates:)`.
struct EquipmentProfileInfo: Identifiable, Hashable {
    var id: UUID
    var name: String
    var isActive: Bool
    var barKg: Double
    var availableEquipment: [String]
    var plateStock: [PlateStock]
    var collarsKg: Double
    /// `EquipmentSeeder`'s stable identity for this profile ("gym"/"home"), `nil` for a
    /// user-created one. See `EquipmentProfileModel.seedKey`.
    var seedKey: String?
}

/// Editable fields for `WorkoutStore.updateProfile(id:draft:)`, bundled so
/// the call site doesn't exceed the lint's parameter-count limit.
struct EquipmentProfileDraft {
    var name: String
    var barKg: Double = 20
    var availableEquipment: [String] = []
    var plateStock: [PlateStock] = []
    var collarsKg: Double = 0
}

extension WorkoutStore {
    func equipmentProfiles() -> [EquipmentProfileInfo] {
        let descriptor = FetchDescriptor<EquipmentProfileModel>(sortBy: [SortDescriptor(\.createdAt)])
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map(equipmentProfileInfo)
    }

    /// The profile marked active, or the first profile when none is (so
    /// callers always have something to load plates from once at least one
    /// profile exists).
    func activeProfile() -> EquipmentProfileInfo? {
        let profiles = equipmentProfiles()
        return profiles.first(where: \.isActive) ?? profiles.first
    }

    /// Marks exactly one profile active, deactivating every other one.
    func setActive(id: UUID) {
        let models = (try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []
        for model in models {
            model.isActive = model.id == id
        }
        save()
    }

    @discardableResult
    func createProfile(
        name: String, isActive: Bool = false, barKg: Double = 20,
        availableEquipment: [String] = [], plateStock: [PlateStock] = [], collarsKg: Double = 0,
        seedKey: String? = nil
    ) -> EquipmentProfileInfo {
        if isActive { deactivateAll() }
        let model = EquipmentProfileModel(
            name: name, isActive: isActive, barKg: barKg, availableEquipment: availableEquipment,
            plateStockKg: plateStock.map(\.weightKg), plateCounts: plateStock.map(\.count),
            collarsKg: collarsKg, seedKey: seedKey
        )
        context.insert(model)
        save()
        return equipmentProfileInfo(for: model)
    }

    @discardableResult
    func updateProfile(id: UUID, draft: EquipmentProfileDraft) -> EquipmentProfileInfo? {
        guard let model = fetchEquipmentProfileModel(id: id) else { return nil }
        model.name = draft.name
        model.barKg = draft.barKg
        model.availableEquipment = draft.availableEquipment
        model.plateStockKg = draft.plateStock.map(\.weightKg)
        model.plateCounts = draft.plateStock.map(\.count)
        model.collarsKg = draft.collarsKg
        save()
        return equipmentProfileInfo(for: model)
    }

    /// Deletes a profile, promoting another one to active if the deleted
    /// profile was active and at least one remains.
    func deleteProfile(id: UUID) {
        guard let model = fetchEquipmentProfileModel(id: id) else { return }
        let wasActive = model.isActive
        context.delete(model)
        save()
        if wasActive, let fallback = equipmentProfiles().first {
            setActive(id: fallback.id)
        }
    }

    /// The plate inventory for a profile, ready for `PlateCalculator`.
    func plateStock(for profile: EquipmentProfileInfo) -> [PlateStock] { profile.plateStock }

    /// Equipment kinds (`EquipmentOption` raw values) in the active profile — what the library
    /// and picker show by default. Nil when no profile exists yet, which means "no filter".
    func activeEquipmentKinds() -> Set<String>? {
        activeProfile().map { Set($0.availableEquipment) }
    }

    func fetchEquipmentProfileModel(id: UUID) -> EquipmentProfileModel? {
        var descriptor = FetchDescriptor<EquipmentProfileModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func deactivateAll() {
        let models = (try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []
        for model in models { model.isActive = false }
    }

    private func equipmentProfileInfo(for model: EquipmentProfileModel) -> EquipmentProfileInfo {
        let stock = zip(model.plateStockKg, model.plateCounts).map { PlateStock(weightKg: $0, count: $1) }
        return EquipmentProfileInfo(
            id: model.id, name: model.name, isActive: model.isActive, barKg: model.barKg,
            availableEquipment: model.availableEquipment, plateStock: stock, collarsKg: model.collarsKg,
            seedKey: model.seedKey
        )
    }
}

extension EquipmentProfileInfo {
    /// False for a profile that lists every equipment kind (the seeded "Gym"): filtering by it
    /// would change nothing, so the library skips the "Showing what's in …" banner for it.
    var restrictsLibrary: Bool {
        !EquipmentOption.allCases.allSatisfy { availableEquipment.contains($0.rawValue) }
    }
}

extension RoutineInfo {
    /// Equipment kinds this routine's exercises need that `available` doesn't list, in
    /// first-use order and without repeats. Empty means the routine can be done as-is.
    func equipmentOutside(_ available: Set<String>) -> [String] {
        var seen: Set<String> = []
        return exercises.map(\.equipment).filter { kind in
            !available.contains(kind) && seen.insert(kind).inserted
        }
    }
}

/// Seeds "Gym" (standard kg plates, every equipment kind) and "Home"
/// (dumbbell/bodyweight/bands, no plates) once per store
/// (`SeedStateModel.equipmentSeeded`), and only while the store has no
/// profiles at all. Idempotent, like `ExerciseSeeder`/`RoutineSeeder`.
@MainActor
enum EquipmentSeeder {
    static func seedIfNeeded(store: WorkoutStore) {
        let state = SeedState.row(in: store.context)
        defer { store.dedupeEquipmentProfiles() }
        guard !state.equipmentSeeded else { return }
        if store.equipmentProfiles().isEmpty {
            store.createProfile(
                name: "Gym", isActive: true, barKg: Bar.olympic.weightKg,
                availableEquipment: EquipmentOption.allCases.map(\.rawValue),
                plateStock: PlateStock.standardKg, seedKey: "gym"
            )
            store.createProfile(
                name: "Home", isActive: false, barKg: Bar.olympic.weightKg,
                availableEquipment: ["dumbbell", "bodyweight", "bands"], plateStock: [], seedKey: "home"
            )
        }
        state.equipmentSeeded = true
        state.updatedAt = Date()
        store.save()
    }
}

extension WorkoutStore {
    /// Folds duplicate equipment profiles two devices can each produce by seeding "Gym"/"Home"
    /// before the other's rows synced down — the same class of race `ExerciseSeeder.dedupe(in:)`
    /// handles for exercises. Seeded profiles fold on `seedKey` (stable even after the user edits
    /// one copy's name or plates, unlike a fields-equality match); profiles predating `seedKey`
    /// (and any user-created profile that happens to be named "Gym"/"Home") get backfilled first
    /// so existing installs' pre-existing duplicates clean up the same way. Anything left over —
    /// genuinely custom, unkeyed profiles — still folds if every field matches, the original
    /// safety net. The survivor is the oldest (by `id` on a tie) and active if any copy was.
    /// Returns the number removed.
    @discardableResult
    func dedupeEquipmentProfiles() -> Int {
        let models = (try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []
        backfillLegacyEquipmentSeedKeys(models)
        var removed = foldEquipmentProfiles(groupedBySeedKey: models)
        removed += foldEquipmentProfiles(groupedByFieldsEquality: models.filter { $0.seedKey == nil })
        if removed > 0 { save() }
        return removed
    }

    /// A profile seeded before `seedKey` existed has none; match it back to its seed identity by
    /// name so it folds with any newer, correctly-keyed copy instead of surviving as an orphan.
    private func backfillLegacyEquipmentSeedKeys(_ models: [EquipmentProfileModel]) {
        for model in models where model.seedKey == nil {
            switch model.name {
            case "Gym": model.seedKey = "gym"
            case "Home": model.seedKey = "home"
            default: break
            }
        }
    }

    private func foldEquipmentProfiles(groupedBySeedKey models: [EquipmentProfileModel]) -> Int {
        var groups: [String: [EquipmentProfileModel]] = [:]
        for model in models {
            guard let key = model.seedKey else { continue }
            groups[key, default: []].append(model)
        }
        return foldEquipmentProfileGroups(groups)
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
        return foldEquipmentProfileGroups(groups)
    }

    private func foldEquipmentProfileGroups(_ groups: [String: [EquipmentProfileModel]]) -> Int {
        var removed = 0
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            let survivor = ordered[0]
            for duplicate in ordered.dropFirst() {
                survivor.isActive = survivor.isActive || duplicate.isActive
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }
}
