import Foundation
import SwiftData
import os

private let seedLogger = Logger(subsystem: "dev.abdirahmanmohamed.dagym", category: "seeder")

/// Loads `Resources/Seed/exercises.json` into the store on first launch.
/// Idempotent: re-running only inserts exercises whose `seedID` is missing.
/// When the bundled seed's `version` is newer than the version this store last
/// applied (`SeedStateModel.exerciseSeedVersion`), existing rows have their
/// instructions/provenance fields refreshed without duplicating rows.
@MainActor
enum ExerciseSeeder {

    struct SeedFile: Decodable {
        var version: Int
        var source: String
        var exercises: [SeedExercise]
    }

    struct SeedExercise: Decodable {
        var id: String
        var name: String
        var primary: [String]
        var secondary: [String]
        var equipment: String
        var mechanic: String?
        var loggingStyle: String
        var isPerSide: Bool
        var bar: String?
        var incrementKg: Double
        var restSeconds: Int
        var instructions: String?
        var source: String?
        var sourceURL: String?
        var licence: String?
        var authors: [String]?
    }

    enum SeederError: Error {
        case resourceNotFound
    }

    /// Every store read `dedupe(in:)` has issued, for `SeedDedupePerformanceTests`. The pass
    /// runs after every remote change, so its query count must stay flat in the number of
    /// tombstones — the same discipline `WorkoutStore.queryCount` enforces on session builds.
    static var dedupeQueryCount = 0

    private static func fetch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>, in context: ModelContext
    ) -> [T] {
        dedupeQueryCount += 1
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Inserts every seeded exercise not already present, keyed by `seedID`.
    /// Refreshes existing rows' provenance fields when the seed version bumped.
    static func seedIfNeeded(context: ModelContext, bundle: Bundle = .main) {
        do {
            let seed = try loadSeed(bundle: bundle)
            try insertMissing(seed.exercises, into: context)
            let state = SeedState.row(in: context)
            if seed.version > state.exerciseSeedVersion {
                try updateExisting(seed.exercises, from: state.exerciseSeedVersion, in: context)
                state.exerciseSeedVersion = seed.version
                state.updatedAt = Date()
                try context.save()
            }
            if dedupe(in: context) > 0 { try context.save() }
        } catch {
            seedLogger.error("Exercise seeding failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The decoded bundled seed, for callers that need to compare a row against its seeded values
    /// (`BackupService` decides "is this an override?" this way).
    nonisolated static func loadSeed(bundle: Bundle = .main) throws -> SeedFile {
        try JSONDecoder().decode(SeedFile.self, from: loadSeedData(bundle: bundle))
    }

    /// How long a folded-away row is kept before it is really deleted. CloudKit imports a
    /// record's children long after the record itself, so a loser is only safe to delete once
    /// nothing has pointed at it for well past any plausible import window — and a second
    /// device can sit offline (signed out, Wi-Fi-only, on holiday) for weeks while still
    /// logging against its copy. A tombstone is cheap; a lost session is not.
    static let tombstoneGracePeriod: TimeInterval = 30 * 24 * 60 * 60

    /// Folds rows that share a `seedID` (two devices each seeded before the other's rows synced)
    /// into one survivor — the oldest, by `id` on a tie so every device picks the same one — and
    /// re-points routine slots, workout entries, exercise notes and PR rows/events at it.
    ///
    /// The loser is **tombstoned** (`mergedIntoID`), not deleted. Deleting it was a permanent
    /// history loss: CloudKit delivers a record's children after the record, so the other
    /// device's `WorkoutExerciseModel`/`RoutineExerciseModel`/PR rows landed *after* the fold
    /// with nothing to link to, and the delete then synced back and nulled that device's own
    /// rows too. Keeping the loser alive means those late arrivals still resolve, and the next
    /// pass (`RemoteChangeDeduper` runs one after every remote batch) re-points them. Ripe
    /// tombstones — merged longer ago than `tombstoneGracePeriod`, still childless — are swept.
    ///
    /// Returns the number of rows folded or swept this pass; 0 when there was nothing to do, so
    /// repeated passes are no-ops.
    @discardableResult
    static func dedupe(in context: ModelContext) -> Int {
        let models = fetch(FetchDescriptor<ExerciseModel>(), in: context)
        var bySeedID: [String: [ExerciseModel]] = [:]
        for model in models {
            if let seedID = model.seedID { bySeedID[seedID, default: []].append(model) }
        }
        let groups = bySeedID.filter { $0.value.count > 1 }
        // Nothing shares a seedID and nothing is tombstoned: the common case on a single
        // device, and the pass must cost one query — it runs after every remote change.
        guard !groups.isEmpty || models.contains(where: \.isMergedAway) else { return 0 }
        // Every child that a fold might have to re-point, read once for the whole pass.
        // Before this, each duplicate cost its own three predicate fetches plus two
        // relationship faults, and a settled tombstone paid that again on every pass: the
        // owner's store (one tombstone per seeded exercise after an iCloud double-seed) spent
        // ~3 s on the main thread per pass — twice at launch and once more after every
        // CloudKit transaction, which is what froze scrolling while a sync was running.
        let children = FoldChildren(context: context)
        let seeded = try? loadSeed()
        var seedByID: [String: SeedExercise] = [:]
        for item in seeded?.exercises ?? [] { seedByID[item.id] = item }
        var folded = 0
        for (seedID, group) in groups {
            let ordered = group.sorted(by: survivesFirst)
            let survivor = ordered[0]
            if survivor.isMergedAway {
                survivor.mergedIntoID = nil
                survivor.mergedAt = nil
            }
            for duplicate in ordered.dropFirst() {
                let changed = fold(
                    duplicate, into: survivor, seed: seedByID[seedID], children: children
                )
                if changed { folded += 1 }
            }
        }
        let swept = sweepTombstones(models, children: children, context: context)
        if folded + swept > 0 {
            seedLogger.info(
                "Seed fold: \(folded, privacy: .public) folded, \(swept, privacy: .public) swept"
            )
        }
        return folded + swept
    }

    static func survivesFirst(_ lhs: ExerciseModel, _ rhs: ExerciseModel) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Re-points everything that named `duplicate` at `survivor` and tombstones it. Returns
    /// whether anything actually changed, so an already-settled tombstone doesn't keep counting
    /// as work and re-triggering `rebuildPersonalRecords()` on every remote change. Every write
    /// is guarded on the value differing: SwiftData marks a row dirty even when the new value
    /// equals the old, and a pass that "re-wrote" ~1 500 settled tombstones then paid a full
    /// save for nothing.
    @discardableResult
    private static func fold(
        _ duplicate: ExerciseModel, into survivor: ExerciseModel, seed: SeedExercise?,
        children: FoldChildren
    ) -> Bool {
        var changed = duplicate.mergedIntoID != survivor.id
        let slots = children.slots(of: duplicate)
        let entries = children.entries(of: duplicate)
        changed = changed || !slots.isEmpty || !entries.isEmpty
        for slot in slots { slot.exercise = survivor }
        for entry in entries { entry.exercise = survivor }
        changed = repointBareIDs(from: duplicate, to: survivor, children: children) || changed
        mergeFields(from: duplicate, into: survivor, seed: seed)
        if duplicate.mergedIntoID != survivor.id { duplicate.mergedIntoID = survivor.id }
        if duplicate.mergedAt == nil { duplicate.mergedAt = Date() }
        return changed
    }

    /// The references held as a bare `UUID` rather than a SwiftData relationship (CloudKit
    /// forbids a relationship here — see each model's doc comment), so SwiftData does not
    /// re-point them for us: the PR cache, the PR *event* log, and exercise notes. A PR event
    /// left dangling is a record History and the weekly recap silently stop counting.
    private static func repointBareIDs(
        from duplicate: ExerciseModel, to survivor: ExerciseModel, children: FoldChildren
    ) -> Bool {
        let duplicateID = duplicate.id
        let survivorID = survivor.id
        guard duplicateID != survivorID else { return false }
        let records = children.records[duplicateID] ?? []
        for record in records { record.exerciseID = survivorID }
        let events = children.events[duplicateID] ?? []
        for event in events { event.exerciseID = survivorID }
        let notes = children.notes[duplicateID] ?? []
        for note in notes { note.exerciseID = survivorID }
        return !records.isEmpty || !events.isEmpty || !notes.isEmpty
    }

    /// Carries the loser's user-editable fields onto the survivor. Anything the survivor still
    /// holds at its seeded value is treated as unedited, so a rest time, increment or bar the
    /// user changed on whichever copy lost the fold is kept rather than discarded. Rest is the
    /// exception: its unedited value is 0 ("use the default"), not the seed's number — and a
    /// copy seeded by a device still on seed v3 carries the seed's number for unedited rest,
    /// which must not land on the survivor as an override.
    private static func mergeFields(
        from duplicate: ExerciseModel, into survivor: ExerciseModel, seed: SeedExercise?
    ) {
        if !survivor.isFavorite, duplicate.isFavorite { survivor.isFavorite = true }
        if survivor.notes.isEmpty, !duplicate.notes.isEmpty { survivor.notes = duplicate.notes }
        if survivor.restSeconds == 0, duplicate.restSeconds != 0,
           duplicate.restSeconds != seed?.restSeconds {
            survivor.restSeconds = duplicate.restSeconds
        }
        guard let seed else { return }
        if survivor.incrementKg == seed.incrementKg, duplicate.incrementKg != seed.incrementKg {
            survivor.incrementKg = duplicate.incrementKg
        }
        if survivor.barType == seed.bar, duplicate.barType != seed.bar {
            survivor.barType = duplicate.barType
        }
    }

    /// Deletes tombstones that have been merged for longer than `tombstoneGracePeriod` and
    /// still have nothing pointing at them. Anything that acquired a child in the meantime is
    /// left alone — the next `dedupe` pass re-points it and restarts the clock at `mergedAt`.
    private static func sweepTombstones(
        _ models: [ExerciseModel], children: FoldChildren, context: ModelContext
    ) -> Int {
        let cutoff = Date().addingTimeInterval(-tombstoneGracePeriod)
        var swept = 0
        for model in models {
            guard model.isMergedAway, let mergedAt = model.mergedAt, mergedAt < cutoff,
                  children.slots(of: model).isEmpty, children.entries(of: model).isEmpty,
                  !children.hasBareIDReferences(model) else { continue }
            context.delete(model)
            swept += 1
        }
        return swept
    }

    private static func insertMissing(_ items: [SeedExercise], into context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<ExerciseModel>())
        var existingIDs = Set(existing.compactMap(\.seedID))
        var insertedCount = 0
        for item in items where !existingIDs.contains(item.id) {
            let model = ExerciseModel(
                seedID: item.id, name: item.name, primaryMuscles: item.primary,
                secondaryMuscles: item.secondary, equipment: item.equipment, mechanic: item.mechanic,
                loggingStyle: item.loggingStyle, isPerSide: item.isPerSide, barType: item.bar,
                // 0 = "use Settings → Default rest". The seed's own `restSeconds` is only ever
                // an explicit per-exercise override, and a fresh row has none.
                incrementKg: item.incrementKg, restSeconds: 0,
                instructions: item.instructions ?? "", dataSource: item.source ?? "",
                sourceURL: item.sourceURL ?? "", licence: item.licence ?? "",
                authors: item.authors ?? []
            )
            context.insert(model)
            existingIDs.insert(item.id)
            insertedCount += 1
        }
        if insertedCount > 0 {
            try context.save()
            seedLogger.info("Seeded \(insertedCount, privacy: .public) exercises")
        }
    }

    /// Updates instructions/provenance on rows that already exist, matched by
    /// `seedID`. Never inserts or duplicates rows.
    ///
    /// Seed version 4 also migrates rest: seeded rows used to carry the seed's `restSeconds` as
    /// their own value, so Settings → Default rest never applied to them. A row still at its
    /// seed item's number is unedited and becomes 0 ("use the default"); one the lifter changed
    /// is an override and is kept. The rest migration runs once per store — only when the store
    /// is coming from a version before `restMigrationVersion` — so a rest the lifter later sets
    /// to exactly the seed's number is not flipped back to "default" by every future bump.
    static func updateExisting(
        _ items: [SeedExercise], from previousVersion: Int, in context: ModelContext
    ) throws {
        let existing = try context.fetch(FetchDescriptor<ExerciseModel>())
        var bySeedID: [String: ExerciseModel] = [:]
        for model in existing where !model.isMergedAway {
            if let seedID = model.seedID {
                bySeedID[seedID] = model
            }
        }
        var updatedCount = 0
        for item in items {
            guard let model = bySeedID[item.id] else { continue }
            refresh(model, from: item, migrateRest: previousVersion < restMigrationVersion)
            updatedCount += 1
        }
        if updatedCount > 0 {
            try context.save()
            seedLogger.info("Updated \(updatedCount, privacy: .public) exercises to newer seed version")
        }
    }

    /// The seed version that moved unedited rest from the seed's number to 0.
    static let restMigrationVersion = 4

    private static func refresh(_ model: ExerciseModel, from item: SeedExercise, migrateRest: Bool) {
        if let instructions = item.instructions, !instructions.isEmpty {
            model.instructions = instructions
        }
        if let source = item.source { model.dataSource = source }
        if let sourceURL = item.sourceURL { model.sourceURL = sourceURL }
        if let licence = item.licence { model.licence = licence }
        if let authors = item.authors { model.authors = authors }
        if migrateRest, model.restSeconds == item.restSeconds { model.restSeconds = 0 }
    }

    /// The seed JSON lives at `Resources/Seed/exercises.json`. Swift Testing
    /// structs don't have a `Bundle(for:)` peer, so we try the passed-in
    /// bundle, then `Bundle(identifier:)`, then every loaded bundle.
    nonisolated private static func loadSeedData(bundle: Bundle) throws -> Data {
        if let url = seedURL(in: bundle) {
            return try Data(contentsOf: url)
        }
        if let named = Bundle(identifier: "dev.abdirahmanmohamed.dagym"), let url = seedURL(in: named) {
            return try Data(contentsOf: url)
        }
        for candidate in Bundle.allBundles {
            if let url = seedURL(in: candidate) {
                return try Data(contentsOf: url)
            }
        }
        throw SeederError.resourceNotFound
    }

    nonisolated private static func seedURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "exercises", withExtension: "json", subdirectory: "Seed")
            ?? bundle.url(forResource: "exercises", withExtension: "json")
    }
}

extension ExerciseSeeder {
    /// The rows a fold re-points, indexed by the exercise they name — five fetches for the
    /// whole pass instead of five per duplicate. The relationship children are only prefetched
    /// for exercises already tombstoned (the settled case that repeats every pass); a fresh
    /// duplicate reads its own relationships once, as before.
    @MainActor
    struct FoldChildren {
        private(set) var records: [UUID: [PersonalRecordModel]] = [:]
        private(set) var events: [UUID: [PersonalRecordEventModel]] = [:]
        private(set) var notes: [UUID: [ExerciseNoteModel]] = [:]
        private var slots: [PersistentIdentifier: [RoutineExerciseModel]] = [:]
        private var entries: [PersistentIdentifier: [WorkoutExerciseModel]] = [:]

        init(context: ModelContext) {
            for record in fetch(FetchDescriptor<PersonalRecordModel>(), in: context) {
                if let id = record.exerciseID { records[id, default: []].append(record) }
            }
            for event in fetch(FetchDescriptor<PersonalRecordEventModel>(), in: context) {
                if let id = event.exerciseID { events[id, default: []].append(event) }
            }
            for note in fetch(FetchDescriptor<ExerciseNoteModel>(), in: context) {
                if let id = note.exerciseID { notes[id, default: []].append(note) }
            }
            // Filtered on the Date twin of `mergedIntoID` (stamped and cleared together in
            // `dedupe`/`fold`): the same optional-UUID-against-nil shape that
            // `WorkoutStore.liveExercises` documents as silently empty is avoided here on
            // principle, and `SeedDedupePerformanceTests.tombstoneChildPrefetchIsExact` pins
            // that the fetch returns exactly the tombstones' children.
            let tombstoneSlots = FetchDescriptor<RoutineExerciseModel>(
                predicate: #Predicate { $0.exercise?.mergedAt != nil }
            )
            for slot in fetch(tombstoneSlots, in: context) {
                if let owner = slot.exercise { slots[owner.persistentModelID, default: []].append(slot) }
            }
            let tombstoneEntries = FetchDescriptor<WorkoutExerciseModel>(
                predicate: #Predicate { $0.exercise?.mergedAt != nil }
            )
            for entry in fetch(tombstoneEntries, in: context) {
                if let owner = entry.exercise { entries[owner.persistentModelID, default: []].append(entry) }
            }
        }

        func slots(of exercise: ExerciseModel) -> [RoutineExerciseModel] {
            exercise.isMergedAway
                ? slots[exercise.persistentModelID] ?? [] : exercise.routineExercises ?? []
        }

        func entries(of exercise: ExerciseModel) -> [WorkoutExerciseModel] {
            exercise.isMergedAway
                ? entries[exercise.persistentModelID] ?? [] : exercise.workoutExercises ?? []
        }

        func hasBareIDReferences(_ exercise: ExerciseModel) -> Bool {
            let id = exercise.id
            return !(records[id] ?? []).isEmpty || !(events[id] ?? []).isEmpty || !(notes[id] ?? []).isEmpty
        }
    }
}
