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
        let models = fetch(descriptor)
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
        let models = fetch(FetchDescriptor<EquipmentProfileModel>())
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

    /// The one bar/plate inventory every surface must agree on — the set row's plate chip, the
    /// weight keypad's live plate line, the 1RM calculator's percent table and the progression
    /// engine's rounding. It is the *active equipment profile*; a generic standard set is only
    /// the fallback for a store that has no profile yet, and even then it follows the lifter's
    /// unit. Before this, the chip used `WeightUnit.plateStock(for:)` while the engine used the
    /// profile, so the app called its own prescription unloadable and named plates the lifter
    /// does not own.
    func activeInventory() -> ProgressionEquipment {
        guard let profile = activeProfile() else {
            let unit = preferredWeightUnit
            return ProgressionEquipment(
                bar: unit.defaultBar, plates: WeightUnit.plateStock(for: unit), collarsKg: 0
            )
        }
        return ProgressionEquipment(
            bar: Bar(name: profile.name, weightKg: profile.barKg), plates: profile.plateStock,
            collarsKg: profile.collarsKg
        )
    }

    /// `Preferences.weightUnit`, read straight from storage. The store has no `Preferences`
    /// (it outlives and underlies the view tree), and this is only ever the fallback path.
    var preferredWeightUnit: WeightUnit {
        let raw = UserDefaults.standard.string(forKey: Preferences.Key.weightUnit) ?? ""
        return WeightUnit(rawValue: raw) ?? .kg
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
        return fetchFirst(descriptor)
    }

    private func deactivateAll() {
        let models = fetch(FetchDescriptor<EquipmentProfileModel>())
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
///
/// What goes into each profile lives on `SeededEquipmentProfile`, not here, so
/// `dedupeEquipmentProfiles()` can compare a row against the exact values that
/// were seeded and never mistake a user's own "Gym" for one of these.
@MainActor
enum EquipmentSeeder {
    /// - Parameter unit: the unit the lifter picked during onboarding. "Gym" is seeded with
    ///   that unit's bar and plates, so a lb lifter's prescriptions land on weights an American
    ///   rack can build instead of on kg-loadable numbers like 62.5 kg ("137.8 lb").
    static func seedIfNeeded(store: WorkoutStore, unit: WeightUnit = .kg) {
        let state = SeedState.row(in: store.context)
        defer { store.dedupeEquipmentProfiles() }
        guard !state.equipmentSeeded else { return }
        if store.equipmentProfiles().isEmpty {
            for seed in SeededEquipmentProfile.allCases {
                store.createProfile(
                    name: seed.name, isActive: seed.isActiveWhenSeeded, barKg: seed.barKg(for: unit),
                    availableEquipment: seed.availableEquipment, plateStock: seed.plateStock(for: unit),
                    collarsKg: seed.collarsKg, seedKey: seed.key
                )
            }
        }
        state.equipmentSeeded = true
        state.updatedAt = Date()
        store.save()
    }
}
