import Foundation
import GymCore
import Testing

@testable import DaGym

/// The media aliases (`exercise-media-aliases.json`) and the photo credits
/// (`exercise-photo-credits.json`): both ship as data, so these pin what the code assumes about
/// them — every alias target has media of its own, nothing chains, every credited photo is
/// bundled, and the hero follows the alias to the right picture and the right credit line.
@Suite("Exercise media aliases and credits")
struct ExerciseMediaTests {
    @Test("the alias file parses into a few hundred entries")
    func aliasFileParses() {
        #expect(ExerciseMediaAliases.aliases.count > 300)
        #expect(ExerciseMediaAliases.resolve("Not_A_Seed_ID") == "Not_A_Seed_ID")
        #expect(!ExerciseMediaAliases.isAliased("Barbell_Deadlift"))
    }

    @Test("every alias source is a seeded exercise, and every target has art or photographs")
    func everyTargetHasMedia() throws {
        let seedIDs = Set(try ExerciseSeeder.loadSeed().exercises.map(\.id))
        for (source, target) in ExerciseMediaAliases.aliases {
            #expect(seedIDs.contains(source), "\(source) is not in the seed")
            #expect(seedIDs.contains(target), "\(source) → \(target) is not in the seed")
            #expect(Self.hasOwnMedia(target), "\(source) → \(target) has no media of its own")
        }
    }

    @Test("no alias points at another alias, and nothing aliases an exercise that has its own media")
    func noChainsOrCycles() {
        for (source, target) in ExerciseMediaAliases.aliases {
            #expect(!ExerciseMediaAliases.isAliased(target), "\(source) → \(target) chains on")
            #expect(source != target)
            #expect(!Self.hasOwnMedia(source), "\(source) has media and should not be aliased")
        }
    }

    @Test("pinned examples resolve to the same movement")
    func pinnedExamples() {
        #expect(ExerciseMediaAliases.resolve("2_Handed_Kettlebell_Swing") == "Kettlebell_Swing")
        #expect(ExerciseMediaAliases.resolve("Deadlifts") == "Barbell_Deadlift")
        #expect(ExerciseMediaAliases.resolve("Facepull") == "Face_Pull")
        #expect(ExerciseMediaAliases.resolve("Alternate_back_lunges") == "Dumbbell_Rear_Lunge")
        #expect(ExerciseMediaAliases.resolve("45_lateral_raises") == "Lateral_Raises")
        // A row is not a pulldown, and a hip thrust is not a squat: neither may be aliased across.
        #expect(!ExerciseMediaAliases.resolve("Row").contains("Pulldown"))
        #expect(!ExerciseMediaAliases.resolve("Glute_Drive").contains("Squat"))
    }

    @Test("the hero follows the alias: art where the twin has art, photo where it has photos")
    func heroFollowsAlias() {
        // Deadlifts → Barbell_Deadlift, which has illustrated art.
        #expect(ExerciseHeroMedia.choice(for: "Deadlifts") == .vector("Barbell_Deadlift"))
        // Barbell_Hack_Squats → Barbell_Hack_Squat, which has photographs only.
        #expect(ExerciseHeroMedia.choice(for: "Barbell_Hack_Squats") == .photo("Barbell_Hack_Squat"))
        // Hollow_Hold has neither art nor photographs, so the generated frames carry it.
        #expect(ExerciseHeroMedia.choice(for: "Hollow_Hold") == .frames("Hollow_Hold"))
        // An unaliased exercise with nothing still falls back to the body map.
        #expect(ExerciseHeroMedia.choice(for: "External_Rotation_Stretch") == .none)
    }

    @Test("every credited photograph is bundled, licence-clean, and captioned only when owed")
    func creditsAreBundledAndCaptioned() {
        #expect(ExercisePhotoCredits.credits.count > 60)
        let allowed: Set<String> = [
            "Public domain", "CC0", "CC BY 2.0", "CC BY 3.0", "CC BY 4.0",
            "CC BY-SA 2.0", "CC BY-SA 3.0", "CC BY-SA 4.0"
        ]
        for (seedID, credit) in ExercisePhotoCredits.credits {
            #expect(ExercisePhotoCatalog.hasPhotos(for: seedID), "\(seedID) is credited but not bundled")
            #expect(allowed.contains(credit.licence), "\(seedID): \(credit.licence)")
            #expect(!credit.author.isEmpty && !credit.sourceURL.isEmpty, "\(seedID) has no traceable origin")
            #expect(credit.frames.count == (ExercisePhotoCatalog.singleFrameSeedIDs.contains(seedID) ? 1 : 2))
            if credit.requiresAttribution {
                #expect(credit.captionLine == "Photo: \(credit.author) · \(credit.licence)")
            } else {
                #expect(credit.captionLine == nil)
            }
        }
        // The free-exercise-db pairs are not in the credits file and so caption nothing.
        #expect(ExercisePhotoCredits.credit(for: "Ab_Roller") == nil)
        // A wger Everkinetic drawing is CC BY-SA and says so.
        let frontSquat = ExercisePhotoCredits.credit(for: "Front_Squats")
        #expect(frontSquat?.captionLine == "Photo: Everkinetic · CC BY-SA 3.0")
    }

    /// With the generated frames in, every seeded exercise but three has a picture of its own
    /// or borrows one; the three left are pinned so a regression in any catalogue shows here.
    @Test("1,463 of 1,466 seeded exercises reach a picture through art, frames, photos or an alias")
    func coverage() throws {
        let seedIDs = try ExerciseSeeder.loadSeed().exercises.map(\.id)
        let uncovered = seedIDs.filter { ExerciseHeroMedia.choice(for: $0) == .none }.sorted()
        #expect(seedIDs.count == 1466)
        #expect(uncovered == ["External_Rotation_Stretch", "Shrimp_Squad", "Tibialis_raises"])
    }

    private static func hasOwnMedia(_ seedID: String) -> Bool {
        ExerciseArtCatalog.frames(for: seedID) != nil
            || ExerciseFrameCatalog.hasFrames(for: seedID)
            || ExercisePhotoCatalog.hasPhotos(for: seedID)
    }
}
