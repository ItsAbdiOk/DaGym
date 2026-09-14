import Foundation
import GymCore
import Testing

@testable import DaGym

/// Coverage for the `ExerciseModel.seedID` → `ExerciseInfo.seedID` → `ExerciseArtCatalog` chain
/// that drives the illustrated hero art on `ExerciseDetailView`.
@Suite("Exercise art")
struct ExerciseArtTests {
    @Test("ExerciseInfo built from a model carries the seedID through")
    func seedIDCarriesThrough() {
        let model = ExerciseModel(
            seedID: "Barbell_Squat", name: "Barbell Squat", primaryMuscles: [Muscle.quads.rawValue],
            equipment: "Barbell"
        )

        let info = ExerciseInfo(model: model)

        #expect(info.seedID == "Barbell_Squat")
        #expect(ExerciseArtCatalog.frames(for: info.seedID ?? "") != nil)
    }

    @Test("an exercise with no matching art returns nil frames cleanly")
    func noArtReturnsNilFrames() {
        let model = ExerciseModel(
            seedID: "Some_Exercise_Without_Art", name: "Some Exercise",
            primaryMuscles: [Muscle.chest.rawValue],
            equipment: "Barbell"
        )

        let info = ExerciseInfo(model: model)

        #expect(info.seedID == "Some_Exercise_Without_Art")
        #expect(ExerciseArtCatalog.frames(for: info.seedID ?? "") == nil)

        // Custom exercises (and any other fixture built without a seedID) carry no art either.
        let custom = ExerciseInfo(name: "My Custom Move", primary: [.chest], equipment: "Barbell")
        #expect(custom.seedID == nil)
        #expect(ExerciseArtCatalog.frames(for: custom.seedID ?? "") == nil)
    }

    @Test("the bundled path data decompresses, parses, and yields three non-empty frames")
    func bundledPathDataParsesForAKnownExercise() async throws {
        let slug = try #require(ExerciseArtCatalog.slug(for: "Barbell_Squat"))
        let frames = try #require(await ExerciseArtPathStore.shared.frames(forSlug: slug))

        #expect(frames.count == 3)
        for frame in frames {
            #expect(!frame.isEmpty)
            #expect(frame.boundingRect.width > 0)
            #expect(frame.boundingRect.height > 0)
        }
    }

    @Test("every slug the catalogue maps to exists in the shipped path-data blob")
    func everyCatalogSlugIsShipped() async {
        let shipped = await ExerciseArtPathStore.shared.allSlugs()
        let missing = Set(ExerciseArtCatalog.slugsBySeedID.values).subtracting(shipped).sorted()

        // A catalogue entry with no blob entry is a silently art-less exercise: the hero falls
        // back to the glyph with nothing to say why. Regenerate both with
        // scripts/import-exercise-art.sh.
        #expect(missing.isEmpty, "catalogue slugs missing from ExerciseArtPaths.zlib: \(missing)")
        #expect(!shipped.isEmpty)
    }

    @Test("a slug with no bundled path data returns nil rather than crashing")
    func unknownSlugReturnsNil() async {
        let frames = await ExerciseArtPathStore.shared.frames(forSlug: "does-not-exist-slug")
        #expect(frames == nil)
    }
}
