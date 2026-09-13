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
        availableEquipment: [String] = [], plateStock: [PlateStock] = [], collarsKg: Double = 0
    ) -> EquipmentProfileInfo {
        if isActive { deactivateAll() }
        let model = EquipmentProfileModel(
            name: name, isActive: isActive, barKg: barKg, availableEquipment: availableEquipment,
            plateStockKg: plateStock.map(\.weightKg), plateCounts: plateStock.map(\.count),
            collarsKg: collarsKg
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
            availableEquipment: model.availableEquipment, plateStock: stock, collarsKg: model.collarsKg
        )
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
                plateStock: PlateStock.standardKg
            )
            store.createProfile(
                name: "Home", isActive: false, barKg: Bar.olympic.weightKg,
                availableEquipment: ["dumbbell", "bodyweight", "bands"], plateStock: []
            )
        }
        state.equipmentSeeded = true
        state.updatedAt = Date()
        store.save()
    }
}

extension WorkoutStore {
    /// Folds profiles that are identical in every field but `id`/`isActive`/`createdAt` — what two
    /// devices seeding "Gym" and "Home" before syncing produce — into the oldest (by `id` on a
    /// tie). The survivor is active if any copy was. Returns the number removed.
    @discardableResult
    func dedupeEquipmentProfiles() -> Int {
        let models = (try? context.fetch(FetchDescriptor<EquipmentProfileModel>())) ?? []
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
        if removed > 0 { save() }
        return removed
    }
}
