import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("Feature: library filtering & routine builder")
struct FeatureLibraryRoutinesTests {
    private func exercise(_ store: WorkoutStore, _ name: String, equipment: String) -> ExerciseInfo {
        store.createCustomExercise(name: name, primary: [.chest], equipment: equipment, style: .weightReps)
    }

    // MARK: - 4. Equipment profile filters

    @Test("activeEquipmentKinds follows the active profile and is nil with no profiles")
    func activeEquipmentKindsFollowsActiveProfile() throws {
        let store = try makeStore()
        #expect(store.activeEquipmentKinds() == nil)

        EquipmentSeeder.seedIfNeeded(store: store)
        #expect(store.activeEquipmentKinds()?.contains("barbell") == true)

        let home = try #require(store.equipmentProfiles().first { $0.name == "Home" })
        store.setActive(id: home.id)
        #expect(store.activeEquipmentKinds() == ["dumbbell", "bodyweight", "bands"])
    }

    @Test("a profile with every equipment kind doesn't restrict the library; Home does")
    func restrictsLibraryOnlyWhenSomethingIsMissing() throws {
        let store = try makeStore()
        EquipmentSeeder.seedIfNeeded(store: store)
        let gym = try #require(store.equipmentProfiles().first { $0.name == "Gym" })
        let home = try #require(store.equipmentProfiles().first { $0.name == "Home" })
        #expect(!gym.restrictsLibrary)
        #expect(home.restrictsLibrary)
    }

    @Test("a routine lists the equipment kinds the active profile lacks, once each, in order")
    func routineReportsEquipmentOutsideProfile() throws {
        let store = try makeStore()
        let bench = exercise(store, "Bench", equipment: "barbell")
        let fly = exercise(store, "Fly", equipment: "dumbbell")
        let dip = exercise(store, "Dip", equipment: "bodyweight")
        let row = exercise(store, "Row", equipment: "machine")
        let squat = exercise(store, "Squat", equipment: "barbell")
        let routine = store.saveRoutine(
            id: nil, name: "Full",
            exercises: [bench, fly, dip, row, squat].map { RoutineExerciseDraft(exerciseID: $0.id) }
        )
        let home: Set<String> = ["dumbbell", "bodyweight", "bands"]
        #expect(routine.equipmentOutside(home) == ["barbell", "machine"])
        #expect(routine.equipmentOutside(["barbell", "dumbbell", "bodyweight", "machine"]).isEmpty)
    }

    // MARK: - 12. Copy routine + glyph

    @Test("symbol and tint save, load through drafts, and default for older routines")
    func glyphRoundTrips() throws {
        let store = try makeStore()
        let bench = exercise(store, "Bench", equipment: "barbell")
        let plain = store.saveRoutine(
            id: nil, name: "Plain", exercises: [RoutineExerciseDraft(exerciseID: bench.id)]
        )
        #expect(plain.symbolName == "dumbbell")
        #expect(plain.tint == "coral")

        let saved = store.saveRoutine(
            id: plain.id, name: "Plain", symbolName: "flame", tint: "violet",
            exercises: [RoutineExerciseDraft(exerciseID: bench.id)]
        )
        #expect(saved.symbolName == "flame")
        #expect(saved.tint == "violet")

        let reloaded = try #require(store.routineDrafts(id: plain.id))
        #expect(reloaded.info.symbolName == "flame")
        #expect(reloaded.info.tint == "violet")
    }

    @Test("saving without a glyph keeps the one already chosen")
    func saveWithoutGlyphKeepsExisting() throws {
        let store = try makeStore()
        let bench = exercise(store, "Bench", equipment: "barbell")
        let routine = store.saveRoutine(
            id: nil, name: "Push", symbolName: "bolt", tint: "gold",
            exercises: [RoutineExerciseDraft(exerciseID: bench.id)]
        )
        let resaved = store.saveRoutine(
            id: routine.id, name: "Push A", exercises: [RoutineExerciseDraft(exerciseID: bench.id)]
        )
        #expect(resaved.symbolName == "bolt")
        #expect(resaved.tint == "gold")
    }

    @Test("copying a routine carries its glyph and appears in the routines list")
    func duplicateCarriesGlyph() throws {
        let store = try makeStore()
        let bench = exercise(store, "Bench", equipment: "barbell")
        let routine = store.saveRoutine(
            id: nil, name: "Push", symbolName: "flame", tint: "red",
            exercises: [RoutineExerciseDraft(exerciseID: bench.id)]
        )
        let copy = try #require(store.duplicateRoutine(id: routine.id))
        #expect(copy.name == "Push (Copy)")
        #expect(copy.symbolName == "flame")
        #expect(copy.tint == "red")
        #expect(store.routines().count == 2)
    }

    @Test("an unknown tint key falls back to coral instead of crashing")
    func unknownTintFallsBack() {
        #expect(RoutineTint.named("neon") == .coral)
        #expect(RoutineTint.named("violet") == .violet)
    }

    @Test("the glyph survives a backup export/import, and old files default it")
    func glyphRoundTripsThroughBackup() throws {
        let store = try makeStore()
        let bench = exercise(store, "Bench", equipment: "barbell")
        store.saveRoutine(
            id: nil, name: "Push", symbolName: "trophy", tint: "green",
            exercises: [RoutineExerciseDraft(exerciseID: bench.id)]
        )
        var document = BackupService.export(context: store.context)
        let exported = try #require(document.routines.first)
        #expect(exported.symbolName == "trophy")
        #expect(exported.tint == "green")

        let destination = try makeStore()
        _ = BackupService.import(document: document, context: destination.context)
        let imported = try #require(destination.routines().first)
        #expect(imported.symbolName == "trophy")
        #expect(imported.tint == "green")

        document.routines[0].symbolName = nil
        document.routines[0].tint = nil
        let legacy = try makeStore()
        _ = BackupService.import(document: document, context: legacy.context)
        let legacyRoutine = try #require(legacy.routines().first)
        #expect(legacyRoutine.symbolName == "dumbbell")
        #expect(legacyRoutine.tint == "coral")
    }

    // MARK: - 15. Drag reorder keeps supersets whole

    @Test("units group adjacent exercises that share a superset")
    func unitsGroupSupersets() {
        #expect(RoutineReorder.units(groups: [nil, 1, 1, nil, 2, 2, 2]) == [[0], [1, 2], [3], [4, 5, 6]])
        #expect(RoutineReorder.units(groups: [1, nil, 1]) == [[0], [1], [2]])
        #expect(RoutineReorder.units(groups: []).isEmpty)
    }

    @Test("moving a superset unit to the front carries both members and keeps their order")
    func moveSupersetAsOneBlock() {
        let names = ["Squat", "Bench", "Row", "Curl"]
        let groups: [Int?] = [nil, 1, 1, nil]
        // Units: [Squat] [Bench+Row] [Curl]; drag unit 1 above unit 0.
        let moved = RoutineReorder.moveUnits(names, groups: groups, fromOffsets: [1], toOffset: 0)
        #expect(moved == ["Bench", "Row", "Squat", "Curl"])
    }

    @Test("moving a single past a superset lands after the whole pair")
    func moveSinglePastSuperset() {
        let names = ["Squat", "Bench", "Row", "Curl"]
        let groups: [Int?] = [nil, 1, 1, nil]
        // Drag unit 0 (Squat) to after unit 1 (Bench+Row) — List.onMove hands over toOffset 2.
        let moved = RoutineReorder.moveUnits(names, groups: groups, fromOffsets: [0], toOffset: 2)
        #expect(moved == ["Bench", "Row", "Squat", "Curl"])
    }

    // MARK: - 28. Loading note + every-set kind

    @Test("a loading note saves with the routine and comes back in the draft")
    func loadingNoteRoundTrips() throws {
        let store = try makeStore()
        let bench = exercise(store, "Bench", equipment: "barbell")
        let draft = RoutineExerciseDraft(
            exerciseID: bench.id, note: "Start at 60 kg, add 2.5 once 3×8 feels easy",
            sets: [PlannedSetDraft(kind: .working, targetReps: 8)]
        )
        let routine = store.saveRoutine(id: nil, name: "Push", exercises: [draft])
        let reloaded = try #require(store.routineDrafts(id: routine.id))
        #expect(reloaded.drafts[0].note == "Start at 60 kg, add 2.5 once 3×8 feels easy")
    }

    @Test("every-set kind stamps each planned set and reads back as uniform")
    func everySetKindStampsAllSets() throws {
        var sets = [
            PlannedSetDraft(kind: .working, targetReps: 8), PlannedSetDraft(kind: .working, targetReps: 8),
            PlannedSetDraft(kind: .warmup, targetReps: 5)
        ]
        #expect(sets.uniformKind == nil)
        sets.setAllKinds(.drop)
        #expect(sets.uniformKind == .drop)
        #expect(sets.map(\.targetReps) == [8, 8, 5])

        let store = try makeStore()
        let bench = exercise(store, "Bench", equipment: "barbell")
        let routine = store.saveRoutine(
            id: nil, name: "Push", exercises: [RoutineExerciseDraft(exerciseID: bench.id, sets: sets)]
        )
        let reloaded = try #require(store.routineDrafts(id: routine.id))
        #expect(reloaded.drafts[0].sets.map(\.kind) == [.drop, .drop, .drop])

        sets.setAllKinds(.working)
        #expect(sets.uniformKind == .working)
        #expect([PlannedSetDraft]().uniformKind == nil)
    }
}
