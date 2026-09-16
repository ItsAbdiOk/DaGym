import Foundation
import GymCore
import SwiftData
import Testing

@testable import DaGym

@MainActor
@Suite("ExerciseSeeder")
struct ExerciseSeederTests {
    @Test("seeding is idempotent and produces 1466 exercises with valid muscle raw values")
    func seedsOnceWithValidMuscles() throws {
        let context = try makeContext()

        ExerciseSeeder.seedIfNeeded(context: context)
        let firstCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(firstCount == 1466)

        ExerciseSeeder.seedIfNeeded(context: context)
        let secondCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(secondCount == firstCount)

        let models = try context.fetch(FetchDescriptor<ExerciseModel>())
        for model in models {
            #expect(model.primaryMuscles.allSatisfy { Muscle(rawValue: $0) != nil })
            #expect(model.secondaryMuscles.allSatisfy { Muscle(rawValue: $0) != nil })
        }
    }

    @Test("a bumped seed version refreshes an existing row's stale instructions and provenance")
    func bumpedVersionUpdatesExistingRows() throws {
        let context = try makeContext()
        // Seed once at version 0 (nothing applied yet), then hand-corrupt one row the way an
        // older seed version would have left it — stale instructions and a placeholder source —
        // so the update pass this test actually exercises has something to fix.
        ExerciseSeeder.seedIfNeeded(context: context)
        let seededCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        let staleBenchPress = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        staleBenchPress.instructions = "stale placeholder instructions"
        staleBenchPress.dataSource = "stale-source"
        SeedState.row(in: context).exerciseSeedVersion = 0
        try context.save()

        // Now seed again as if the bundled seed bumped to version 6 (its real value) — this must
        // refresh the stale row in place, not skip it because `insertMissing` already saw the ID.
        ExerciseSeeder.seedIfNeeded(context: context)
        #expect(SeedState.row(in: context).exerciseSeedVersion == 6)

        let benchPress = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Barbell_Bench_Press_-_Medium_Grip"
            }
        )
        #expect(benchPress.instructions != "stale placeholder instructions")
        #expect(!benchPress.instructions.isEmpty)
        #expect(benchPress.dataSource == "wger")

        // Re-running with the same stored version must not duplicate rows or
        // re-run the (no-op) update pass.
        ExerciseSeeder.seedIfNeeded(context: context)
        let count = try context.fetch(FetchDescriptor<ExerciseModel>()).count
        #expect(count == seededCount)
        #expect(count == 1466)
    }

    @Test("a fresh seed leaves rest at 0 so Settings → Default rest applies")
    func freshRowsHaveNoRestOverride() throws {
        let context = try makeContext()

        ExerciseSeeder.seedIfNeeded(context: context)
        let models = try context.fetch(FetchDescriptor<ExerciseModel>())
        #expect(models.allSatisfy { $0.restSeconds == 0 })
    }

    @Test("an existing install's unedited seeded rest migrates to 0; an edited one is kept")
    func versionBumpMigratesUneditedRestToDefault() throws {
        let context = try makeContext()
        ExerciseSeeder.seedIfNeeded(context: context)
        let seed = try ExerciseSeeder.loadSeed(bundle: Bundle(for: BundleAnchor.self))
        let benchID = "Barbell_Bench_Press_-_Medium_Grip"
        let squatID = "Barbell_Squat"
        let seededBenchRest = try #require(seed.exercises.first { $0.id == benchID }).restSeconds
        let models = try context.fetch(FetchDescriptor<ExerciseModel>())
        let bench = try #require(models.first { $0.seedID == benchID })
        let squat = try #require(models.first { $0.seedID == squatID })
        // What a pre-version-4 install holds: every seeded row carrying the seed's own number
        // (bench), except the ones the lifter changed by hand (squat).
        bench.restSeconds = seededBenchRest
        squat.restSeconds = 240
        SeedState.row(in: context).exerciseSeedVersion = 3
        try context.save()

        ExerciseSeeder.seedIfNeeded(context: context)

        #expect(bench.restSeconds == 0)
        #expect(squat.restSeconds == 240)
        #expect(SeedState.row(in: context).exerciseSeedVersion == 6)
    }

    /// `needsSeeding` is what lets a cold launch skip the 1.4 MB decode: it must say "no" for a
    /// store at the bundled version with rows in it, and "yes" for a version behind or an empty
    /// library (a fresh install, or the store the reset just wiped).
    @Test("a store at the bundled version with rows in it needs no seeding; a stale or empty one does")
    func needsSeedingGatesOnVersionAndCount() throws {
        let context = try makeContext()
        #expect(ExerciseSeeder.needsSeeding(context: context))

        ExerciseSeeder.seedIfNeeded(context: context)
        #expect(!ExerciseSeeder.needsSeeding(context: context))
        #expect(SeedState.row(in: context).exerciseSeedVersion == ExerciseSeeder.bundledVersion)

        SeedState.row(in: context).exerciseSeedVersion = ExerciseSeeder.bundledVersion - 1
        try context.save()
        #expect(ExerciseSeeder.needsSeeding(context: context))
        ExerciseSeeder.seedIfNeeded(context: context)
        #expect(!ExerciseSeeder.needsSeeding(context: context))

        for model in try context.fetch(FetchDescriptor<ExerciseModel>()) { context.delete(model) }
        try context.save()
        #expect(ExerciseSeeder.needsSeeding(context: context))
    }

    /// The pinned constant is the only thing standing between a seed regeneration and a launch
    /// that never notices the new version.
    @Test("bundledVersion matches the version in exercises.json")
    func bundledVersionMatchesTheFile() throws {
        let seed = try ExerciseSeeder.loadSeed(bundle: Bundle(for: BundleAnchor.self))
        #expect(seed.version == ExerciseSeeder.bundledVersion)
    }

    @Test("the off-main variant seeds the same library and is a no-op the second time")
    func asyncSeedMatchesSync() async throws {
        let context = try makeContext()
        await ExerciseSeeder.seedIfNeededAsync(context: context)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseModel>()) == 1466)
        #expect(SeedState.row(in: context).exerciseSeedVersion == ExerciseSeeder.bundledVersion)
        await ExerciseSeeder.seedIfNeededAsync(context: context)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseModel>()) == 1466)
    }

    /// A fresh insert is stamped with the bundled version straight away and is not followed by
    /// the version-bump refresh (`updateExisting`): every row was just written from the file.
    /// Pins the stamp and that the pass leaves the context clean.
    @Test("a fresh install seeds in one pass: version stamped, nothing left to save")
    func freshInstallSeedsInOnePass() throws {
        let context = try makeContext()
        ExerciseSeeder.seedIfNeeded(context: context)
        #expect(!context.hasChanges)
        #expect(SeedState.row(in: context).exerciseSeedVersion == ExerciseSeeder.bundledVersion)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseModel>()) == 1466)
    }

    /// Seed v6 corrected a batch of primary-muscle/equipment tags (`Reverse_Machine_Flyes`
    /// chest → rear delts, `Pec_Deck` bodyweight → machine, and others). A store still on an
    /// older version must pick up the corrected values on the next launch without duplicating
    /// the row — this is what actually gets the fix to a lifter who already has the exercise.
    @Test("a bumped seed version refreshes a stale primary muscle and equipment tag")
    func bumpedVersionFixesMuscleAndEquipment() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let context = ModelContext(container)
        ExerciseSeeder.seedIfNeeded(context: context)
        let seededCount = try context.fetch(FetchDescriptor<ExerciseModel>()).count

        // Hand-corrupt two rows back to their pre-v6 (wrong) tags, as if seeded by an older build.
        let reverseFlyes = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first {
                $0.seedID == "Reverse_Machine_Flyes"
            }
        )
        reverseFlyes.primaryMuscles = ["chest"]
        reverseFlyes.secondaryMuscles = ["delts"]
        let pecDeck = try #require(
            try context.fetch(FetchDescriptor<ExerciseModel>()).first { $0.seedID == "Pec_Deck" }
        )
        pecDeck.equipment = "bodyweight"
        SeedState.row(in: context).exerciseSeedVersion = 5
        try context.save()

        ExerciseSeeder.seedIfNeeded(context: context)

        #expect(reverseFlyes.primaryMuscles == ["delts"])
        #expect(reverseFlyes.secondaryMuscles == ["traps"])
        #expect(pecDeck.equipment == "machine")
        #expect(SeedState.row(in: context).exerciseSeedVersion == ExerciseSeeder.bundledVersion)
        #expect(try context.fetch(FetchDescriptor<ExerciseModel>()).count == seededCount)
    }

    @Test("every seeded exercise has non-empty instructions within a sane length")
    func everyExerciseHasInstructions() throws {
        let context = try makeContext()

        ExerciseSeeder.seedIfNeeded(context: context)
        let models = try context.fetch(FetchDescriptor<ExerciseModel>())
        let total = models.count

        let nonEmptyCount = models.filter { !$0.instructions.isEmpty }.count
        #expect(nonEmptyCount == total)

        // Our own text is capped; wger text is kept verbatim (CC-BY-SA) and may run longer.
        for model in models where model.dataSource != "wger" {
            let wordCount = model.instructions.split(separator: " ").count
            #expect(
                wordCount <= 90,
                "\(model.seedID ?? model.name) has \(wordCount) words"
            )
        }
    }
}

/// Data-integrity tests over the *shipped* seed file (`DaGym/Resources/Seed/exercises.json`),
/// not over hand-built fixtures. Every rule here corresponds to a real defect that shipped to
/// lifters: an importer fallback that made 157 unrelated exercises abs-primary, rows tagged
/// traps-primary because free-exercise-db calls the lats "middle back", exercises listing the
/// same muscle as both a primary and a secondary mover, and secondary lists so long they said
/// nothing. Regenerating the seed has to keep passing these.
@Suite("Seed muscle data")
struct SeedMuscleDataTests {
    /// Exercises that genuinely train no muscle we model, and therefore ship with empty
    /// `primary` *and* `secondary`: rest timers, breathing and meditation drills, self-massage,
    /// pure neck/wrist/ankle mobility (the neck, hands and ankles are drawn inert on the body
    /// map), and work on the tibialis anterior — the shin, which `BodyMapMuscleMapping`
    /// deliberately leaves inert so a clean stops looking like it trains the shins.
    ///
    /// This list is exhaustive and exact on purpose. An exercise that falls out of the muscle
    /// mapping must be named here by a human, so a future seed regeneration cannot quietly
    /// reintroduce a blanket fallback (the bug this whole suite exists for).
    static let nonMuscularSeedIDs: Set<String> = [
        "90_90_Breathing", "Ankle_Roll", "Banded_Ankle_Mobility", "Blackroll",
        "Bobbing_Exhale_Drill", "Chin_tuck", "Clockwise_neck_circles",
        "Counterclockwise_neck_circles", "Deep_breathing_standing_or_seated",
        "Diaphragmatic_Breathing", "Exercise_Band_Dorsiflexion", "Foam_Roller_Anterior_tibialis",
        "Front_neck_stretch", "Guided_or_free_meditation", "Head_tilts", "Head_turns",
        "Kegel_Exercise", "Neck_CARs", "Neck_half_circles", "Plantarflexion_Stretch_with_Band",
        "Recovery_Bobbing", "Rest_for_timed_workouts", "Single_leg_BOSU_balance",
        "Tibialis_raises", "Wrist_circles"
    ]

    /// The only abs-primary exercises whose *name* doesn't say "core". Anything else that wants
    /// to be abs-primary has to look like core work from its name, which is what makes the
    /// "everything unmappable became abs" fallback impossible to reintroduce silently.
    static let absPrimaryNameExceptions: Set<String> = ["Kettlebell_Pass_Between_The_Legs"]

    /// Words that make "this is core work" plausible from the name alone.
    private static let coreNameHints = [
        "crunch", "sit-up", "sit up", "situp", "sit-ups", "ab ", "abs", "abdomin", "plank",
        "core", "leg raise", "knee raise", "knee tuck", "hollow", "dead bug", "deadbug",
        "rollout", "roll out", "roll-over", "l-sit", "l sit", "l hold", "v-sit", "jackknife",
        "scissor", "flutter", "pike", "toes to bar", "wipers", "pull-in", "pull in", "oblique",
        "windshield", "pallof", "leg pull", "leg tuck", "hip raise", "tuck", "fallout",
        "dragon-flag", "dragon flag", "toe tap", "sit out", "ab wheel", "corkscrew",
        "knee slide", "draw-in", "pelvic tilt", "spider crawl", "cobra", "sphinx", "butt-up",
        "bottoms up", "cocoon", "elbow to knee", "air bike", "otis", "leg wheel",
        "mountain climber", "shoulder tap"
    ]

    private static func seed() throws -> [ExerciseSeeder.SeedExercise] {
        try ExerciseSeeder.loadSeed(bundle: Bundle(for: BundleAnchor.self)).exercises
    }

    @Test("no exercise lists the same muscle as both a primary and a secondary mover")
    func noPrimarySecondaryOverlap() throws {
        for exercise in try Self.seed() {
            let overlap = Set(exercise.primary).intersection(exercise.secondary)
            #expect(overlap.isEmpty, "\(exercise.id) lists \(overlap.sorted()) twice")
        }
    }

    @Test("every exercise has at least one primary mover, or is a named non-muscular entry")
    func everyExerciseHasAPrimary() throws {
        let seed = try Self.seed()
        let empty = Set(seed.filter { $0.primary.isEmpty }.map(\.id))
        #expect(
            empty == Self.nonMuscularSeedIDs,
            """
            untagged exercises must be listed in nonMuscularSeedIDs by hand.
            unexpected: \(empty.subtracting(Self.nonMuscularSeedIDs).sorted())
            stale: \(Self.nonMuscularSeedIDs.subtracting(empty).sorted())
            """
        )
    }

    @Test("a non-muscular entry has no secondary movers either")
    func nonMuscularEntriesAreFullyUntagged() throws {
        for exercise in try Self.seed() where exercise.primary.isEmpty {
            #expect(exercise.secondary.isEmpty, "\(exercise.id) has secondaries but no primary")
        }
    }

    @Test("no exercise claims more than two primary movers, or more than four secondaries")
    func moverCountsStayReadable() throws {
        for exercise in try Self.seed() {
            #expect(exercise.primary.count <= 2, "\(exercise.id) has \(exercise.primary.count) primaries")
            #expect(
                exercise.secondary.count <= 4,
                "\(exercise.id) has \(exercise.secondary.count) secondaries"
            )
        }
    }

    @Test("abs is only a primary mover where the name reads like core work")
    func absPrimaryIsPlausible() throws {
        for exercise in try Self.seed() where exercise.primary.contains(Muscle.abs.rawValue) {
            if Self.absPrimaryNameExceptions.contains(exercise.id) { continue }
            let name = exercise.name.lowercased()
            // One literal, not two concatenated: `Comment` is expressible by a string literal,
            // but `"a" + "b"` is a `String` expression and won't convert.
            let hint: Comment = """
                \(exercise.id) is abs-primary but its name doesn't read like core work — add it \
                to absPrimaryNameExceptions on purpose, or tag it correctly
                """
            #expect(Self.coreNameHints.contains(where: name.contains), hint)
        }
    }

    @Test("every muscle raw value in the seed is a real Muscle case")
    func muscleRawValuesAreValid() throws {
        for exercise in try Self.seed() {
            for raw in exercise.primary + exercise.secondary {
                #expect(Muscle(rawValue: raw) != nil, "\(exercise.id) references unknown muscle \(raw)")
            }
        }
    }

    /// Well-known lifts whose primary movers are not a matter of opinion. If a regenerated seed
    /// moves any of these, the regeneration is wrong — this is the list that would have caught
    /// rows tagged traps-primary, deadlifts tagged lowerBack-primary and bench tagged
    /// triceps-primary before any of it reached a lifter.
    @Test("well-known lifts have the primary movers everyone agrees on")
    func spotCheckPrimaryMovers() throws {
        let expected: [String: Set<String>] = [
            "Barbell_Bench_Press_-_Medium_Grip": ["chest"],
            "Bench_Press_-_Powerlifting": ["chest"],
            "Bent_Over_Barbell_Row": ["lats"],
            "Seated_Cable_Rows": ["lats"],
            "One-Arm_Dumbbell_Row": ["lats"],
            "Wide-Grip_Lat_Pulldown": ["lats"],
            "Pullups": ["lats"],
            "Barbell_Deadlift": ["hams", "glutes"],
            "Romanian_Deadlift": ["hams"],
            "Rack_Pulls": ["hams", "glutes"],
            "Trap_Bar_Deadlift": ["hams", "glutes"],
            "Barbell_Squat": ["quads"],
            "Front_Squats": ["quads"],
            "Leg_Press": ["quads"],
            "Standing_Military_Press": ["delts"],
            "Barbell_Curl": ["biceps"],
            "Overhead_Triceps_Extension": ["triceps"],
            "Shrugs_Barbells": ["traps"],
            "Barbell_Hip_Thrust": ["glutes"],
            "Standing_Calf_Raises": ["calves"],
            "Face_Pull": ["delts"],
            "Plank": ["abs"],
            "Jogging": ["quads", "hams"]
        ]
        let byID = Dictionary(uniqueKeysWithValues: try Self.seed().map { ($0.id, $0) })
        for (id, primary) in expected {
            let exercise = try #require(byID[id], "seed is missing \(id)")
            #expect(Set(exercise.primary) == primary, "\(id) primary is \(exercise.primary)")
        }
    }

    @Test("a lift's thumbnail always shows the side its primary mover is drawn on")
    func thumbnailSideShowsThePrimaryMover() throws {
        for exercise in try Self.seed() {
            let primary = exercise.primary.compactMap(Muscle.init(rawValue:))
            guard let first = primary.first else { continue }
            let side = BodyMapMuscleMapping.thumbnailSide(forPrimary: primary)
            #expect(
                BodyMapMuscleMapping.isAddressable(first, on: side),
                "\(exercise.id)'s primary \(first) isn't drawn on the \(side) view"
            )
        }
    }
}

/// Bundle anchor: Swift Testing structs have no `Bundle(for:)` peer, and the seed resource
/// lives in the host app bundle, so the tests need a class to hang `Bundle(for:)` off.
private final class BundleAnchor {}
