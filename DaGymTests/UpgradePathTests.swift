import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

// Every other suite starts from an empty store. Real lifters open the new build on a store the
// OLD build wrote, so this one opens real old stores (`DaGymTests/Fixtures/Stores/<sha>/`),
// runs the same cold-launch sequence the app runs (`LaunchSeeding.run`) and checks that the
// migrations happened and nothing was lost.
//
// Adding a snapshot for a new TestFlight build (~10 minutes, one simulator):
//   1. git worktree add /tmp/dagym-snap-<sha> <sha> && cd /tmp/dagym-snap-<sha> && xcodegen generate
//   2. Drop the throwaway test below into that worktree as DaGymTests/StoreSnapshotWriterTests.swift
//      (do not commit it there; the worktree is deleted in step 5). Replace SNAPSHOT_SHA.
//   3. xcodebuild test -project DaGym.xcodeproj -scheme DaGym -destination 'id=<sim>' \
//        -derivedDataPath /tmp/dagym-dd-snap-<sha> -only-testing:DaGymTests/StoreSnapshotWriterTests
//      It writes /tmp/dagym-snap-out-<sha>/{default.store,expected.json}.
//   4. Fold the WAL into one file and shrink it:
//        sqlite3 /tmp/dagym-snap-out-<sha>/default.store \
//          "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE; VACUUM;"
//        rm -f /tmp/dagym-snap-out-<sha>/default.store-wal /tmp/dagym-snap-out-<sha>/default.store-shm
//      Then copy default.store → DaGymTests/Fixtures/Stores/<sha>/DaGym.store and expected.json
//      beside it, and add <sha> to `StoreSnapshot.shas`. Keep each fixture under ~6 MB.
//   5. git worktree remove --force /tmp/dagym-snap-<sha>; rm -rf /tmp/dagym-dd-snap-<sha>
//      /tmp/dagym-snap-out-<sha>
//   If a step uses an API the old build lacks (say `Preferences(suite:)`), adapt the throwaway
//   test to that build; the harness only needs the store file and the JSON.
//   Builds from 9279515 on ship no starter routines: replace `createProgram` + `startProgram`
//   with `store.adoptStarterPlan(.upperLower, now: now)` (the picker's one tap), rename and
//   edit two of the sample-data trio ("Pull B", "Legs") instead of Full Body B / 5×5 A, and
//   seed one starter nobody uses (`RoutineSeeder.seedStarters(["Full Body C"], store:)`) so
//   the prune still has a candidate; `prunedNames` is then just that one.
//
// The throwaway test (paste as-is, then fix whatever that build's API renamed):
//
//   import Foundation
//   import GymCore
//   import SwiftData
//   import Testing
//   @testable import DaGym
//
//   @Suite("Store snapshot writer", .serialized) @MainActor
//   struct StoreSnapshotWriterTests {
//       @Test func writeSnapshot() throws {
//           let output = URL(fileURLWithPath: "/tmp/dagym-snap-out-SNAPSHOT_SHA")
//           try? FileManager.default.removeItem(at: output)
//           let legacy = output.appendingPathComponent("legacy", isDirectory: true)
//           try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
//           StoreMigration.containerDirectoryOverride = output
//           StoreMigration.legacyDirectoryOverride = legacy
//           defer {
//               StoreMigration.containerDirectoryOverride = nil
//               StoreMigration.legacyDirectoryOverride = nil
//           }
//           let defaults = UserDefaults(suiteName: "snapshot-writer") ?? .standard
//           defaults.removePersistentDomain(forName: "snapshot-writer")
//           let preferences = Preferences(suite: defaults)
//           let now = Date(timeIntervalSince1970: 1_757_500_000) // fixed clock: stable fixture
//           let container = try ModelContainer.dagym(cloudKitEnabled: false)
//           let context = container.mainContext
//           let store = WorkoutStore(context: context)
//           ExerciseSeeder.seedIfNeeded(context: context)
//           RoutineSeeder.seedStarterRoutinesIfNeeded(store: store)  // seedAll on builds after 04949b4
//           EquipmentSeeder.seedIfNeeded(store: store, unit: preferences.weightUnit)
//           SampleDataSeeder.seed(store: store, preferences: preferences, now: now)
//           store.logBodyweight(kg: 82.5, date: now.addingTimeInterval(-3600))
//           let bench = try #require(store.exercises(matching: "Barbell Bench Press - Medium Grip").first)
//           store.addExerciseNote(exerciseID: bench.id, text: "Pinkies on the rings.", scope: .always)
//           let routines = store.routines()
//           func routine(_ name: String) throws -> RoutineInfo {
//               try #require(routines.first { $0.name == name })
//           }
//           let program = try #require(store.createProgram(from: .upperLower))
//           store.startProgram(id: program.id, now: now)
//           store.saveSchedule(WeeklySchedule(days: [.monday: try routine("Full Body A").id]))
//           // Renamed starter (touched by name) and a set-edited one (touched by updatedAt − createdAt).
//           let renamed = try #require(store.fetchRoutineModel(id: try routine("Full Body B").id))
//           let renamedDrafts = try #require(store.routineDrafts(id: renamed.id)).drafts
//           store.saveRoutine(
//               id: renamed.id, name: "Full Body B (mine)", progressionRule: renamed.progressionRule,
//               repRangeLow: renamed.repRangeLow, repRangeHigh: renamed.repRangeHigh,
//               rule: renamed.progressionRuleValue, exercises: renamedDrafts
//           )
//           let edited = try #require(store.fetchRoutineModel(id: try routine("5×5 A").id))
//           edited.createdAt = now.addingTimeInterval(-3600)
//           var drafts = try #require(store.routineDrafts(id: edited.id)).drafts
//           drafts[0].sets.removeLast()
//           store.saveRoutine(
//               id: edited.id, name: edited.name, progressionRule: edited.progressionRule,
//               repRangeLow: edited.repRangeLow, repRangeHigh: edited.repRangeHigh,
//               rule: edited.progressionRuleValue, exercises: drafts
//           )
//           // Look like a store from before the totals columns so the backfill has work to do.
//           let workouts = store.fetch(FetchDescriptor<WorkoutModel>())
//           let totalVolumeKg = workouts.reduce(0.0) { $0 + $1.loadedVolumeKg }
//           let totalSetsDone = workouts.reduce(0) { $0 + $1.loadedSetsDone }
//           for workout in workouts { workout.volumeKg = 0; workout.setsDone = 0 }
//           let state = SeedState.row(in: context)
//           state.workoutTotalsBackfilled = false
//           try context.save()
//           let prunedNames = ["Full Body C", "5×5 B", "5×5 C"]
//           let keptNames = store.routines().map(\.name).filter { !prunedNames.contains($0) }.sorted()
//           let counts: [String: Any] = [
//               "exerciseSeedVersion": state.exerciseSeedVersion,
//               "exercises": try context.fetchCount(FetchDescriptor<ExerciseModel>()),
//               "routines": try context.fetchCount(FetchDescriptor<RoutineModel>()),
//               "routineExercises": try context.fetchCount(FetchDescriptor<RoutineExerciseModel>()),
//               "plannedSets": try context.fetchCount(FetchDescriptor<PlannedSetModel>()),
//               "workouts": try context.fetchCount(FetchDescriptor<WorkoutModel>()),
//               "workoutExercises": try context.fetchCount(FetchDescriptor<WorkoutExerciseModel>()),
//               "sets": try context.fetchCount(FetchDescriptor<SetLogModel>()),
//               "bodyMeasurements": try context.fetchCount(FetchDescriptor<BodyMeasurementModel>()),
//               "exerciseNotes": try context.fetchCount(FetchDescriptor<ExerciseNoteModel>()),
//               "programs": try context.fetchCount(FetchDescriptor<ProgramModel>()),
//               "programWeeks": try context.fetchCount(FetchDescriptor<ProgramWeekModel>()),
//               "schedules": try context.fetchCount(FetchDescriptor<ScheduleModel>()),
//               "equipmentProfiles": try context.fetchCount(FetchDescriptor<EquipmentProfileModel>()),
//               "personalRecords": try context.fetchCount(FetchDescriptor<PersonalRecordModel>()),
//               "personalRecordEvents":
//                   try context.fetchCount(FetchDescriptor<PersonalRecordEventModel>()),
//               "totalVolumeKg": totalVolumeKg, "totalSetsDone": totalSetsDone,
//               "bodyweightKg": 82.5, "noteText": "Pinkies on the rings.",
//               "keptRoutineNames": keptNames, "prunedRoutineNames": prunedNames.sorted()
//           ]
//           let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
//           let data = try JSONSerialization.data(withJSONObject: counts, options: options)
//           try data.write(to: output.appendingPathComponent("expected.json"))
//       }
//   }

/// `.serialized`: every test opens on-disk containers and shares the main actor; running them
/// one at a time keeps the SQLite files and the store-location overrides from interleaving.
@Suite("Upgrade path over real old stores", .serialized)
@MainActor
struct UpgradePathTests {
    private static func freshPreferences(_ name: String) -> Preferences {
        let suite = "upgrade-path-\(name)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return Preferences(suite: defaults)
    }

    // MARK: - Schema safety net

    /// The day someone adds a non-optional field without a default, lightweight migration
    /// fails and this is the test that says so by name, before a lifter's phone does.
    @Test("every snapshot opens under the current schema", arguments: StoreSnapshot.shas)
    func snapshotOpens(sha: String) throws {
        let snapshot = try StoreSnapshot.stage(sha)
        defer { snapshot.cleanUp() }
        do {
            let container = try snapshot.openContainer()
            let context = container.mainContext
            #expect(try context.fetchCount(FetchDescriptor<ExerciseModel>()) == snapshot.expected.exercises)
        } catch {
            let message = "Store written by \(sha) failed to open under the current schema — "
                + "lightweight migration is broken: \(error)"
            Issue.record(Comment(rawValue: message))
        }
    }

    // MARK: - First launch over an old store

    @Test("first launch migrates the seed, prunes untouched starters and keeps every row",
          arguments: StoreSnapshot.shas)
    func firstLaunchOverOldStore(sha: String) async throws {
        let snapshot = try StoreSnapshot.stage(sha)
        defer { snapshot.cleanUp() }
        let expected = snapshot.expected
        let preferences = Self.freshPreferences(sha)
        let container = try snapshot.openContainer()
        let context = container.mainContext
        let store = try snapshot.makeStore(container)

        // What the old build left: its seed version, its (wrong) v5 tags when it predates the
        // v6 refresh, no totals stamped.
        #expect(SeedState.row(in: context).exerciseSeedVersion == expected.exerciseSeedVersion)
        if expected.exerciseSeedVersion < 6 {
            #expect(try Self.exercise("Reverse_Machine_Flyes", in: context).primaryMuscles == ["chest"])
            #expect(try Self.exercise("Pec_Deck", in: context).equipment == "bodyweight")
        }
        let unstamped = try context.fetch(FetchDescriptor<WorkoutModel>())
        #expect(unstamped.allSatisfy { !$0.hasStampedTotals })

        await LaunchSeeding.run(store: store, preferences: preferences)

        // The v6 refresh: same rows, corrected tags, version stamped.
        let state = SeedState.row(in: context)
        #expect(state.exerciseSeedVersion == ExerciseSeeder.bundledVersion)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseModel>()) == 1466)
        #expect(try Self.exercise("Reverse_Machine_Flyes", in: context).primaryMuscles == ["delts"])
        #expect(try Self.exercise("Pec_Deck", in: context).equipment == "machine")

        // Nothing the lifter logged went anywhere.
        let counts = try StoreFingerprint.counts(in: context)
        #expect(counts["workouts"] == expected.workouts)
        #expect(counts["workoutExercises"] == expected.workoutExercises)
        #expect(counts["sets"] == expected.sets)
        #expect(counts["bodyMeasurements"] == expected.bodyMeasurements)
        #expect(counts["exerciseNotes"] == expected.exerciseNotes)
        #expect(counts["programs"] == expected.programs)
        #expect(counts["programWeeks"] == expected.programWeeks)
        #expect(counts["schedules"] == expected.schedules)
        #expect(counts["equipmentProfiles"] == expected.equipmentProfiles)
        #expect(counts["seedStates"] == 1)
        let bodyweights = try context.fetch(FetchDescriptor<BodyMeasurementModel>())
        #expect(bodyweights.first?.bodyweightKg == expected.bodyweightKg)
        #expect(try context.fetch(FetchDescriptor<ExerciseNoteModel>()).first?.text == expected.noteText)
        #expect(store.schedule().dayRoutines.count == 1)
        #expect(store.programs().first?.routineIDs.count == 4)

        // Untouched starters pruned; the ran, scheduled, programmed, renamed and edited ones kept.
        // A build that ships no routines (9279515 on) has only what the sample data and the
        // starter picker seeded, so the kept list is shorter and the pruned one can be empty.
        let live = store.routines().map(\.name).sorted()
        #expect(live == expected.keptRoutineNames)
        #expect(Set(live).isDisjoint(with: expected.prunedRoutineNames))
        #expect(preferences.starterRoutinesPruned)
        #expect(try context.fetchCount(FetchDescriptor<RoutineModel>())
            == expected.routines - expected.prunedRoutineNames.count)

        // Totals stamped on every finished workout, and they add up to what the sets say.
        let workouts = try context.fetch(FetchDescriptor<WorkoutModel>())
        #expect(workouts.allSatisfy { $0.hasStampedTotals })
        #expect(workouts.allSatisfy { $0.volumeKg == $0.loadedVolumeKg })
        #expect(workouts.allSatisfy { $0.setsDone == $0.loadedSetsDone })
        #expect(abs(workouts.reduce(0.0) { $0 + $1.volumeKg } - expected.totalVolumeKg) < 0.01)
        #expect(workouts.reduce(0) { $0 + $1.setsDone } == expected.totalSetsDone)
        #expect(state.workoutTotalsBackfilled)
        #expect(state.healthRowsPurged)

        // The PR cache survives intact and agrees with a rebuild from history.
        #expect(counts["personalRecords"] == expected.personalRecords)
        #expect(counts["personalRecordEvents"] == expected.personalRecordEvents)
        let liveExerciseIDs = Set(try context.fetch(FetchDescriptor<ExerciseModel>()).map(\.id))
        let records = try context.fetch(FetchDescriptor<PersonalRecordModel>())
        #expect(records.allSatisfy { $0.exerciseID.map(liveExerciseIDs.contains) ?? false })

        try Self.expectNoDuplicateSeedRows(in: context)
        #expect(!context.hasChanges)
    }

    // MARK: - Second launch is a no-op

    @Test("a second launch over a migrated store changes nothing", arguments: StoreSnapshot.shas)
    func secondLaunchIsNoOp(sha: String) async throws {
        let snapshot = try StoreSnapshot.stage(sha)
        defer { snapshot.cleanUp() }
        let preferences = Self.freshPreferences("second-\(sha)")
        let first = try snapshot.openContainer()
        await LaunchSeeding.run(store: try snapshot.makeStore(first), preferences: preferences)
        let before = try StoreFingerprint(context: first.mainContext)

        // A fresh container over the same file: what the next cold start actually sees.
        let second = try snapshot.openContainer()
        let store = try snapshot.makeStore(second)
        await LaunchSeeding.run(store: store, preferences: preferences)

        let after = try StoreFingerprint(context: second.mainContext)
        #expect(after == before)
        #expect(!second.mainContext.hasChanges)
        #expect(store.routines().map(\.name).sorted() == snapshot.expected.keptRoutineNames)
        // The cache the launch left is exactly what a rebuild from the same history produces.
        let cachedCount = try second.mainContext.fetchCount(FetchDescriptor<PersonalRecordModel>())
        store.rebuildPersonalRecords()
        #expect(try second.mainContext.fetchCount(FetchDescriptor<PersonalRecordModel>()) == cachedCount)
    }

    // MARK: - Current build over its own store

    @Test("the current build's own on-disk store seeds once and re-opens as a no-op")
    func currentOverCurrent() async throws {
        let snapshot = try StoreSnapshot.fresh()
        defer { snapshot.cleanUp() }
        let preferences = Self.freshPreferences("current")
        let first = try snapshot.openContainer()
        await LaunchSeeding.run(store: try snapshot.makeStore(first), preferences: preferences)
        let context = first.mainContext
        #expect(try context.fetchCount(FetchDescriptor<ExerciseModel>()) == 1466)
        #expect(SeedState.row(in: context).exerciseSeedVersion == ExerciseSeeder.bundledVersion)
        #expect(try context.fetchCount(FetchDescriptor<RoutineModel>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<EquipmentProfileModel>()) > 0)
        let before = try StoreFingerprint(context: context)

        let second = try snapshot.openContainer()
        await LaunchSeeding.run(store: try snapshot.makeStore(second), preferences: preferences)
        let after = try StoreFingerprint(context: second.mainContext)
        #expect(after == before)
        #expect(!second.mainContext.hasChanges)
        try Self.expectNoDuplicateSeedRows(in: second.mainContext)
    }

    // MARK: - Helpers

    private static func exercise(_ seedID: String, in context: ModelContext) throws -> ExerciseModel {
        try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first { $0.seedID == seedID },
            "No exercise with seedID \(seedID)"
        )
    }

    /// One live row per seed identity: exercises by `seedID`, starters by `importedFromID`,
    /// equipment profiles by name.
    private static func expectNoDuplicateSeedRows(in context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<ExerciseModel>()).filter { !$0.isMergedAway }
        let seedIDs = exercises.compactMap(\.seedID)
        #expect(Set(seedIDs).count == seedIDs.count)
        let routines = try context.fetch(FetchDescriptor<RoutineModel>()).filter { !$0.isMergedAway }
        let starterIDs = routines.compactMap(\.importedFromID)
        #expect(Set(starterIDs).count == starterIDs.count)
        let profiles = try context.fetch(FetchDescriptor<EquipmentProfileModel>()).map(\.name)
        #expect(Set(profiles).count == profiles.count)
    }
}
