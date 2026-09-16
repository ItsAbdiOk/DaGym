import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("WorkoutStore equipment profiles")
struct WorkoutStoreEquipmentTests {
    @Test("EquipmentSeeder seeds Gym and Home exactly once")
    func seedsOnce() throws {
        let store = try makeStore()

        EquipmentSeeder.seedIfNeeded(store: store)
        let firstPass = store.equipmentProfiles()
        #expect(firstPass.map(\.name).sorted() == ["Gym", "Home"])
        #expect(firstPass.first { $0.name == "Gym" }?.isActive == true)
        #expect(firstPass.first { $0.name == "Home" }?.isActive == false)

        EquipmentSeeder.seedIfNeeded(store: store)
        let secondPass = store.equipmentProfiles()
        #expect(secondPass.count == 2)
    }

    @Test("seeded Gym profile carries the standard kg plate set; Home has none")
    func seededPlateStock() throws {
        let store = try makeStore()

        EquipmentSeeder.seedIfNeeded(store: store)
        let profiles = store.equipmentProfiles()
        let gym = try #require(profiles.first { $0.name == "Gym" })
        let home = try #require(profiles.first { $0.name == "Home" })

        #expect(store.plateStock(for: gym).count == PlateStock.standardKg.count)
        #expect(store.plateStock(for: home).isEmpty)
        #expect(gym.availableEquipment.contains("barbell"))
        #expect(home.availableEquipment.contains("dumbbell"))
        #expect(!home.availableEquipment.contains("barbell"))
    }

    @Test("setActive switches which single profile is active")
    func activeSwitching() throws {
        let store = try makeStore()

        EquipmentSeeder.seedIfNeeded(store: store)
        let home = try #require(store.equipmentProfiles().first { $0.name == "Home" })

        store.setActive(id: home.id)
        let profiles = store.equipmentProfiles()
        #expect(profiles.first { $0.id == home.id }?.isActive == true)
        #expect(profiles.filter(\.isActive).count == 1)
        #expect(store.activeProfile()?.id == home.id)
    }

    @Test("createProfile and updateProfile round trip name, bar, plates and equipment")
    func createAndUpdate() throws {
        let store = try makeStore()

        let created = store.createProfile(
            name: "Garage", barKg: 15, availableEquipment: ["dumbbell"],
            plateStock: [PlateStock(weightKg: 10, count: 4)], collarsKg: 1
        )
        #expect(created.barKg == 15)
        #expect(store.plateStock(for: created).first?.weightKg == 10)

        let draft = EquipmentProfileDraft(
            name: "Garage Gym", barKg: 20, availableEquipment: ["dumbbell", "kettlebell"],
            plateStock: [PlateStock(weightKg: 20, count: 2)], collarsKg: 0
        )
        let updated = try #require(store.updateProfile(id: created.id, draft: draft))
        #expect(updated.name == "Garage Gym")
        #expect(updated.barKg == 20)
        #expect(updated.availableEquipment.sorted() == ["dumbbell", "kettlebell"])
        #expect(store.plateStock(for: updated) == [PlateStock(weightKg: 20, count: 2)])
    }

    @Test("deleting the active profile promotes another one to active")
    func deleteActivePromotesFallback() throws {
        let store = try makeStore()

        EquipmentSeeder.seedIfNeeded(store: store)
        let gym = try #require(store.equipmentProfiles().first { $0.name == "Gym" })

        store.deleteProfile(id: gym.id)
        let remaining = store.equipmentProfiles()
        #expect(remaining.count == 1)
        #expect(remaining.first?.isActive == true)
    }

    // MARK: - Dedupe safety

    @Test("a user-created profile named Gym survives the seed-key backfill and fold")
    func userCreatedGymSurvivesDedupe() throws {
        let store = try makeStore(seed: .equipment)

        // Their own "Gym": a 15 kg bar and a short plate set, nothing like the seeded one.
        let mine = store.createProfile(
            name: "Gym", barKg: 15,
            availableEquipment: ["barbell", "bodyweight"],
            plateStock: [PlateStock(weightKg: 20, count: 2), PlateStock(weightKg: 5, count: 4)]
        )

        // Runs on every launch; used to stamp `mine` with seedKey "gym" and delete it.
        #expect(store.dedupeEquipmentProfiles() == 0)
        #expect(store.dedupeEquipmentProfiles() == 0)

        let profiles = store.equipmentProfiles()
        #expect(profiles.count == 3)
        let survivor = try #require(profiles.first { $0.id == mine.id })
        #expect(survivor.barKg == 15)
        #expect(survivor.plateStock.count == 2)
        #expect(survivor.seedKey == nil)
    }

    @Test("an untouched legacy profile is re-keyed and folds; a renamed one is left alone")
    func renamedLegacyDuplicateIsNeverFoldedAway() throws {
        let (store, context) = try makeStoreAndContext(seed: .equipment)

        // Two pre-`seedKey` rows synced down later: one still exactly as seeded, one the user
        // renamed. Both are newer than the seeded rows, so neither is the fold's survivor.
        let later = Date().addingTimeInterval(60)
        let untouched = legacyGym(named: "Gym", createdAt: later)
        let renamed = legacyGym(named: "Commercial Gym", createdAt: later)
        context.insert(untouched)
        context.insert(renamed)
        try context.save()

        #expect(store.dedupeEquipmentProfiles() == 1)

        let names = store.equipmentProfiles().map(\.name).sorted()
        #expect(names == ["Commercial Gym", "Gym", "Home"])
        // The rename is the user's, so it keeps its own identity rather than being merged away.
        #expect(store.equipmentProfiles().first { $0.name == "Commercial Gym" }?.seedKey == nil)
    }

    @Test("a fold that leaves two profiles active is normalised back to one")
    func twoActiveProfilesNormaliseToOne() throws {
        let (store, context) = try makeStoreAndContext(seed: .equipment)

        let models = try context.fetch(FetchDescriptor<EquipmentProfileModel>())
        for model in models { model.isActive = true }
        try context.save()
        #expect(store.equipmentProfiles().filter(\.isActive).count == 2)

        store.dedupeEquipmentProfiles()

        let active = store.equipmentProfiles().filter(\.isActive)
        #expect(active.count == 1)
        // The oldest wins, which is the one `activeProfile()` would have silently picked anyway.
        #expect(active.first?.name == "Gym")
        #expect(store.activeProfile()?.id == active.first?.id)
    }

    /// A profile as `EquipmentSeeder` wrote it before `seedKey` existed: seeded values, no key.
    private func legacyGym(named name: String, createdAt: Date) -> EquipmentProfileModel {
        let seed = SeededEquipmentProfile.gym
        return EquipmentProfileModel(
            name: name, isActive: false, barKg: seed.barKg(for: .kg),
            availableEquipment: seed.availableEquipment,
            plateStockKg: seed.plateStock(for: .kg).map(\.weightKg),
            plateCounts: seed.plateStock(for: .kg).map(\.count),
            collarsKg: seed.collarsKg, createdAt: createdAt, seedKey: nil
        )
    }
}

/// One inventory, three surfaces. The plate chip, the keypad's plate line and the progression
/// engine all used to answer from different plate sets, so the app could call its own
/// prescription unloadable and name plates the lifter does not own.
@MainActor
@Suite("Equipment: one source of truth")
struct EquipmentSourceOfTruthTests {
    @Test("a lb lifter is seeded a lb bar and lb plates, not a 20 kg bar and kg plates")
    func seedsInTheChosenUnit() throws {
        let store = try makeStore()
        EquipmentSeeder.seedIfNeeded(store: store, unit: .lb)
        let gym = try #require(store.equipmentProfiles().first { $0.name == "Gym" })

        #expect(abs(gym.barKg - WeightUnit.lb.toKg(45)) < 0.001)
        let pounds = gym.plateStock.map { (WeightUnit.lb.display(kg: $0.weightKg) * 2).rounded() / 2 }
        #expect(pounds == [45, 35, 25, 10, 5, 2.5])
        // Every weight the engine can prescribe is one this rack can build.
        let equipment = store.activeEquipment()
        for step in 0...200 {
            let target = Double(step) * 2.5
            let rounded = LoadGrid.plates(
                bar: equipment.bar, plates: equipment.plates, collarsKg: equipment.collarsKg
            ).nearest(target)
            guard case .exact = PlateCalculator.load(
                target: rounded, bar: equipment.bar, plates: equipment.plates,
                collarsKg: equipment.collarsKg
            ) else {
                Issue.record("\(rounded) kg is not loadable on the seeded lb rack")
                continue
            }
        }
    }

    @Test("seeding stays idempotent and dedupe-safe whichever unit seeded it")
    func lbSeedIsNotADuplicate() throws {
        let store = try makeStore()
        EquipmentSeeder.seedIfNeeded(store: store, unit: .lb)
        EquipmentSeeder.seedIfNeeded(store: store, unit: .lb)
        #expect(store.equipmentProfiles().count == 2)
        #expect(store.dedupeEquipmentProfiles() == 0)
    }

    @Test("chip, keypad and engine all read the active profile's inventory")
    func surfacesAgree() throws {
        let store = try makeStore()
        // A rack with 25s and 10s and nothing else — the standard set would disagree loudly.
        let coarse = [PlateStock(weightKg: 25, count: 4), PlateStock(weightKg: 10, count: 2)]
        store.createProfile(
            name: "Coarse", isActive: true, barKg: 20, availableEquipment: ["barbell"],
            plateStock: coarse, collarsKg: 0
        )

        let inventory = store.activeInventory()
        #expect(inventory.plates == coarse)
        // `activeEquipment()` (the engine) and `activeInventory()` (chip + keypad) are one call.
        #expect(store.activeEquipment().plates == inventory.plates)
        #expect(store.activeEquipment().bar.weightKg == inventory.bar.weightKg)

        // The engine's own next step from 40 kg, and what the chip would say about it.
        let grid = LoadGrid.plates(bar: inventory.bar, plates: inventory.plates, collarsKg: 0)
        let next = grid.nearestAbove(40)
        #expect(next == 70)
        let chip = PlateChip.text(
            for: PlateCalculator.load(target: next, bar: inventory.bar, plates: inventory.plates),
            format: { WorkoutSession.format($0) }
        )
        #expect(chip == "Bar 20 · 25 per side")
    }

    @Test("with no profile at all the fallback still follows the lifter's unit")
    func fallbackFollowsUnit() throws {
        let store = try makeStore()
        // The store reads `UserDefaults.standard`, so assert the shape of the fallback rather
        // than mutating global defaults from a test.
        #expect(store.equipmentProfiles().isEmpty)
        let fallback = store.activeInventory()
        #expect(fallback.plates == WeightUnit.plateStock(for: store.preferredWeightUnit))
        #expect(fallback.bar.weightKg == store.preferredWeightUnit.defaultBar.weightKg)
    }

    @Test("opening a kg-seeded profile as a lb lifter keeps its plates")
    func editorKeepsForeignUnitPlates() {
        let kgStock = PlateStock.standardKg
        let rows = EquipmentStep.rows(
            standard: EquipmentStep.standardWeightsKg(for: .lb), existing: kgStock
        )
        // Every saved kg plate survives with its count …
        for plate in kgStock {
            let row = rows.first { abs($0.weightKg - plate.weightKg) < 0.001 }
            #expect(row?.count == plate.count)
        }
        // … and the lb sizes are offered alongside, at zero.
        for weight in EquipmentStep.standardWeightsKg(for: .lb) {
            #expect(rows.contains { abs($0.weightKg - weight) < EquipmentStep.sameSizeToleranceKg })
        }
        // Saving keeps only stocked rows, so nothing is silently wiped.
        #expect(rows.filter { $0.count >= 1 }.count == kgStock.count)
    }
}
