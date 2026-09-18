import Foundation
import GymCore
import Testing

@testable import DaGym

/// Coverage for the `seedID` → `ExercisePhotoCatalog` → bundled HEIC chain that puts a
/// photographed start/end position on `ExerciseDetailView` for the ~700 exercises that have no
/// illustrated vector art, and for the precedence rule between the two.
@Suite("Exercise photos")
struct ExercisePhotoTests {
    /// Photographs but no vector art — the case the whole feature exists for.
    private static let photoOnlySeedID = "Ab_Roller"
    /// Both a photograph and illustrated art, so the hero must choose.
    private static let bothSeedID = "Barbell_Deadlift"
    /// Illustrated art, no photograph.
    private static let vectorOnlySeedID = "Abdominal_Crunch"
    /// One frame from wger (Everkinetic drawing), no end position — no cross-fade.
    private static let singleFrameSeedID = "Front_Squats"

    @Test("a known seedID resolves to two photo files that exist in the bundle")
    func knownSeedIDResolvesToBundledFiles() throws {
        let names = try #require(ExercisePhotoCatalog.photoNames(for: Self.photoOnlySeedID))
        #expect(names.start == "\(Self.photoOnlySeedID)-0")
        #expect(names.end == "\(Self.photoOnlySeedID)-1")

        let urls = try #require(ExercisePhotoStore.bundledURLs(forSeedID: Self.photoOnlySeedID))
        let end = try #require(urls.end)
        for url in [urls.start, end] {
            let size = try #require(
                try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
            )
            #expect(size > 0, "empty photo shipped at \(url.lastPathComponent)")
        }
        #expect(urls.start != end)
    }

    @Test("a single-frame exercise resolves to a start frame only, and still decodes")
    func singleFrameResolvesWithoutAnEnd() async throws {
        let names = try #require(ExercisePhotoCatalog.photoNames(for: Self.singleFrameSeedID))
        #expect(names.start == "\(Self.singleFrameSeedID)-0")
        #expect(names.end == nil)
        #expect(ExercisePhotoCatalog.singleFrameSeedIDs.contains(Self.singleFrameSeedID))

        let urls = try #require(ExercisePhotoStore.bundledURLs(forSeedID: Self.singleFrameSeedID))
        #expect(urls.end == nil)
        let pair = try #require(await ExercisePhotoStore.shared.photos(forSeedID: Self.singleFrameSeedID))
        #expect(pair.end == nil)
    }

    @Test("the bundled photos actually decode into a pair of images")
    func bundledPhotosDecode() async {
        let pair = await ExercisePhotoStore.shared.photos(forSeedID: Self.photoOnlySeedID)
        #expect(pair != nil)
    }

    @Test("an exercise with no photo returns nil cleanly")
    func noPhotoReturnsNil() async {
        #expect(ExercisePhotoCatalog.photoNames(for: "Some_Exercise_Without_Photos") == nil)
        #expect(!ExercisePhotoCatalog.hasPhotos(for: "Some_Exercise_Without_Photos"))
        #expect(ExercisePhotoStore.bundledURLs(forSeedID: "Some_Exercise_Without_Photos") == nil)
        #expect(await ExercisePhotoStore.shared.photos(forSeedID: "Some_Exercise_Without_Photos") == nil)

        // A custom exercise has no seedID at all, so it never reaches the catalogue.
        let custom = ExerciseInfo(name: "My Custom Move", primary: [.chest], equipment: "Barbell")
        #expect(custom.seedID == nil)
        #expect(ExerciseHeroMedia.choice(for: custom.seedID) == .none)
    }

    @Test("an exercise with both vector art and a photo shows the vector art")
    func vectorArtWinsOverPhoto() {
        // Guard the fixture first: if either side of the overlap disappears this test would
        // otherwise pass for the wrong reason.
        #expect(ExerciseArtCatalog.frames(for: Self.bothSeedID) != nil)
        #expect(ExercisePhotoCatalog.hasPhotos(for: Self.bothSeedID))

        #expect(ExerciseHeroMedia.choice(for: Self.bothSeedID) == .vector(Self.bothSeedID))
    }

    @Test("photographs are used only when there is no illustration, and nothing otherwise")
    func heroPrecedenceAcrossTheOtherCases() {
        #expect(ExerciseHeroMedia.choice(for: Self.photoOnlySeedID) == .photo(Self.photoOnlySeedID))
        #expect(ExerciseHeroMedia.choice(for: Self.vectorOnlySeedID) == .vector(Self.vectorOnlySeedID))
        #expect(ExerciseHeroMedia.choice(for: "Nothing_Visual_Here") == .none)
        #expect(ExerciseHeroMedia.choice(for: nil) == .none)
    }

    @Test("every catalogued exercise has both of its photos in the bundle")
    func everyCatalogEntryIsShipped() {
        let missing = ExercisePhotoCatalog.seedIDs
            .filter { ExercisePhotoStore.bundledURLs(forSeedID: $0) == nil }
            .sorted()

        // A catalogue entry with no file is a hero that silently renders a grey placeholder for
        // ever. Regenerate both with scripts/import-exercise-photos.sh or
        // scripts/import-exercise-photos-extra.py.
        #expect(missing.isEmpty, "catalogued exercises with no bundled photos: \(missing)")
        #expect(ExercisePhotoCatalog.seedIDs.count > 700)
        #expect(ExercisePhotoCatalog.singleFrameSeedIDs.isSubset(of: ExercisePhotoCatalog.seedIDs))
    }

    @Test("seeded exercises with a photo carry their seedID through to ExerciseInfo")
    func seedIDCarriesThrough() {
        let model = ExerciseModel(
            seedID: Self.photoOnlySeedID, name: "Ab Roller", primaryMuscles: [Muscle.abs.rawValue],
            equipment: "Other"
        )

        let info = ExerciseInfo(model: model)

        #expect(info.seedID == Self.photoOnlySeedID)
        #expect(ExercisePhotoCatalog.hasPhotos(for: info.seedID ?? ""))
    }
}
