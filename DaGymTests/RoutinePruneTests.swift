import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

/// The one-time prune for installs that seeded all 13 starters before the app stopped shipping
/// routines (`RoutineSeeder.pruneUntouchedStartersOnce`): every starter the lifter never made
/// theirs goes; anything renamed, run, programmed or scheduled stays.
@MainActor
@Suite("Starter routine prune")
struct RoutinePruneTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func routine(_ store: WorkoutStore, named name: String) throws -> RoutineInfo {
        try #require(store.routines().first { $0.name == name })
    }

    @Test("an untouched stocked store loses all 13 starters, once, and the flag stops a second pass")
    func prunesEveryUntouchedStarter() throws {
        let store = try makeStore(seed: .stocked)
        let preferences = Preferences(suite: makeSuite(#function))
        #expect(store.routines().count == 13)

        #expect(RoutineSeeder.pruneUntouchedStartersOnce(store: store, preferences: preferences) == 13)

        #expect(store.routines().isEmpty)
        #expect(preferences.starterRoutinesPruned)
        // A starter seeded after the pass (a program picked later) is not touched by a relaunch.
        _ = store.createProgram(from: .fullBody)
        #expect(RoutineSeeder.pruneUntouchedStartersOnce(store: store, preferences: preferences) == 0)
        #expect(store.routines().count == 3)
    }

    @Test("renamed, run, programmed, scheduled and date-overridden starters survive; the rest go")
    func keepsTouchedStarters() throws {
        let store = try makeStore(seed: .stocked)
        let preferences = Preferences(suite: makeSuite(#function))

        let renamed = try routine(store, named: "Push A")
        store.saveRoutine(id: renamed.id, name: "Push Day", exercises: [])
        let run = try routine(store, named: "Pull B")
        store.context.insert(WorkoutModel(title: "Pull B", endedAt: Date(), routineID: run.id))
        let scheduled = try routine(store, named: "Legs")
        let overridden = try routine(store, named: "Upper A")
        store.saveSchedule(WeeklySchedule(
            dayRoutines: [.monday: [scheduled.id]], dateOverrides: ["2026-09-20": [overridden.id]]
        ))
        let programmed = try #require(store.createProgram(from: .fiveByFive))
        let mine = store.saveRoutine(id: nil, name: "Arms", exercises: [])
        store.save()

        let pruned = RoutineSeeder.pruneUntouchedStartersOnce(store: store, preferences: preferences)

        // 13 starters − Push A, Pull B, Legs, Upper A, 5×5 A/B/C = 6 pruned.
        #expect(pruned == 6)
        let survivors = Set(store.routines().map(\.id))
        let expected = Set([renamed.id, run.id, scheduled.id, overridden.id, mine.id] + programmed.routineIDs)
        #expect(survivors == expected)
        let gone = ["Lower A", "Upper B", "Lower B", "Full Body A"]
        #expect(!store.routines().contains { gone.contains($0.name) })
    }

    @Test("a starter that lost a fold is a tombstone the prune leaves to the sweep")
    func ignoresTombstones() throws {
        let (store, context) = try makeStoreAndContext(seed: .exercises)
        let survivor = RoutineModel(name: "Legs", importedFromID: RoutineSeeder.starterIDs["Legs"])
        let tombstone = RoutineModel(name: "Legs", importedFromID: RoutineSeeder.starterIDs["Legs"])
        tombstone.mergedIntoID = survivor.id
        tombstone.mergedAt = Date()
        context.insert(survivor)
        context.insert(tombstone)
        try context.save()

        #expect(RoutineSeeder.untouchedStarters(store: store).map(\.id) == [survivor.id])
    }

    @Test("a wipe resets the flag so the (empty) store is judged again next launch")
    func wipeResetsFlag() throws {
        let store = try makeStore()
        let preferences = Preferences(suite: makeSuite(#function))
        preferences.starterRoutinesPruned = true

        store.wipeAllData(preferences: preferences, effects: .inert)

        #expect(!preferences.starterRoutinesPruned)
    }
}
