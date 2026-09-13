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
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

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
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

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
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

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
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

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
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        let store = WorkoutStore(context: context)

        EquipmentSeeder.seedIfNeeded(store: store)
        let gym = try #require(store.equipmentProfiles().first { $0.name == "Gym" })

        store.deleteProfile(id: gym.id)
        let remaining = store.equipmentProfiles()
        #expect(remaining.count == 1)
        #expect(remaining.first?.isActive == true)
    }
}
