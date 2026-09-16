import Foundation
import SwiftData
import Testing

@testable import DaGym

// The one place a hosted suite gets an in-memory `WorkoutStore` from. Every store here is
// backed by a fresh `ModelContainer.dagym(inMemory: true)` with CloudKit mirroring off, plus
// throwaway photo and Health containers — exactly what `WorkoutStore(context:)` builds for
// previews — so a suite never shares rows with another and never touches the on-disk store.
//
// A suite that needs a store with something already in it says so with `seed:` rather than
// running the seeders by hand; a suite that only inserts rows takes `makeContext()` and skips
// the store (and its two extra containers) altogether.

/// What a fresh store is pre-populated with. Seeding runs in dependency order: the exercise
/// library first (the starter routines and the equipment profiles both name exercises).
struct TestSeed: OptionSet, Sendable {
    let rawValue: Int

    /// The bundled exercise library (`ExerciseSeeder`).
    static let exercises = TestSeed(rawValue: 1 << 0)
    /// The starter routines (`RoutineSeeder`); pulls in `.exercises`.
    static let routines = TestSeed(rawValue: 1 << 1)
    /// The stock equipment profiles (`EquipmentSeeder`).
    static let equipment = TestSeed(rawValue: 1 << 2)
    /// Everything a first launch seeds.
    static let firstLaunch: TestSeed = [.exercises, .routines, .equipment]
}

/// A bare main-store context, seeded as asked, with no `WorkoutStore` in front of it.
@MainActor
func makeContext(seed: TestSeed = []) throws -> ModelContext {
    let context = try makeLibraryContext(seed)
    if !seed.isDisjoint(with: [.routines, .equipment]) {
        // The store-level seeders only need a store over the same context; the caller's own
        // store (if any) reads the rows back like any other.
        seedThroughStore(WorkoutStore(context: context, photoContext: nil), seed)
    }
    return context
}

/// An in-memory store, seeded as asked, on a fresh context; `units` is the unit provider the
/// store formats and converts with (the default reads `UserDefaults`, like the app).
@MainActor
func makeStore(seed: TestSeed = [], units: StoreUnitProvider = .userDefaults()) throws -> WorkoutStore {
    try makeStoreAndContext(seed: seed, units: units).store
}

/// `makeStore` plus the context behind it, for suites that insert or fetch rows directly.
@MainActor
func makeStoreAndContext(
    seed: TestSeed = [], units: StoreUnitProvider = .userDefaults()
) throws -> (store: WorkoutStore, context: ModelContext) {
    let context = try makeLibraryContext(seed)
    let store = WorkoutStore(
        context: context,
        photoContext: ModelContext(try ModelContainer.dagymPhotos(inMemory: true)),
        healthContext: ModelContext(try ModelContainer.dagymHealth(inMemory: true)),
        units: units
    )
    seedThroughStore(store, seed)
    return (store, context)
}

/// A fresh context with the exercise library in it when `seed` needs one.
@MainActor
private func makeLibraryContext(_ seed: TestSeed) throws -> ModelContext {
    let context = ModelContext(try ModelContainer.dagym(inMemory: true))
    if !seed.isDisjoint(with: [.exercises, .routines]) {
        ExerciseSeeder.seedIfNeeded(context: context)
    }
    return context
}

@MainActor
private func seedThroughStore(_ store: WorkoutStore, _ seed: TestSeed) {
    if seed.contains(.routines) { RoutineSeeder.seedStarterRoutinesIfNeeded(store: store) }
    if seed.contains(.equipment) { EquipmentSeeder.seedIfNeeded(store: store) }
}
