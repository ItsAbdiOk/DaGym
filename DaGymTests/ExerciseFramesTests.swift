import Foundation
import GymCore
import Testing

@testable import DaGym

/// Coverage for the `seedID` → `ExerciseFrameCatalog` → bundled HEIC chain that puts generated
/// 3-frame line-art on `ExerciseDetailView` for the exercises that had neither illustrated art
/// nor photographs, and for where it sits in the hero's precedence order.
@Suite("Exercise generated frames")
struct ExerciseFramesTests {
    /// Generated frames, no art and no photographs — the case the feature exists for.
    private static let framesOnlySeedID = "Hollow_Hold"
    /// Illustrated art, no frames.
    private static let vectorSeedID = "Abdominal_Crunch"
    /// Photographs, no frames.
    private static let photoSeedID = "Ab_Roller"

    @Test("the catalogue lists 218 exercises and every one has all three frames in the bundle")
    func catalogueMatchesBundle() throws {
        #expect(ExerciseFrameCatalog.seedIDs.count == 218)
        #expect(ExerciseFrameCatalog.frameCount == 3)
        for seedID in ExerciseFrameCatalog.seedIDs {
            let urls = try #require(
                ExerciseFrameStore.bundledURLs(forSeedID: seedID), "\(seedID) is missing a frame"
            )
            #expect(urls.count == 3)
            for url in urls {
                let size = try #require(
                    try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
                )
                #expect(size > 0, "empty frame shipped at \(url.lastPathComponent)")
            }
        }
    }

    @Test("frame names follow the <seedID>-<index> convention, in movement order")
    func frameNames() throws {
        let names = try #require(ExerciseFrameCatalog.frameNames(for: Self.framesOnlySeedID))
        #expect(names == ["Hollow_Hold-0", "Hollow_Hold-1", "Hollow_Hold-2"])
        #expect(ExerciseFrameCatalog.frameNames(for: "Some_Exercise_Without_Frames") == nil)
        #expect(!ExerciseFrameCatalog.hasFrames(for: "Some_Exercise_Without_Frames"))
    }

    @Test("every catalogued id is a seeded exercise")
    func everyIDIsSeeded() throws {
        let seedIDs = Set(try ExerciseSeeder.loadSeed().exercises.map(\.id))
        for seedID in ExerciseFrameCatalog.seedIDs {
            #expect(seedIDs.contains(seedID), "\(seedID) has frames but is not in the seed")
        }
    }

    @Test("the bundled frames decode into three images, and the thumbnail store serves the middle one")
    func bundledFramesDecode() async throws {
        let frames = try #require(await ExerciseFrameStore.shared.frames(forSeedID: Self.framesOnlySeedID))
        #expect(frames.count == 3)
        let thumbnail = await MachineThumbnailStore.shared.frameThumbnail(forSeedID: Self.framesOnlySeedID)
        #expect(thumbnail != nil)
        let none = await ExerciseFrameStore.shared.frames(forSeedID: "Some_Exercise_Without_Frames")
        #expect(none == nil)
    }

    @Test("the hero prefers drawn art over frames, and frames over photographs")
    func heroPrecedence() {
        #expect(ExerciseHeroMedia.choice(for: Self.framesOnlySeedID) == .frames(Self.framesOnlySeedID))
        #expect(ExerciseHeroMedia.choice(for: Self.vectorSeedID) == .vector(Self.vectorSeedID))
        #expect(ExerciseHeroMedia.choice(for: Self.photoSeedID) == .photo(Self.photoSeedID))
        #expect(ExerciseHeroMedia.choice(for: nil) == .none)
    }

    /// The frames were generated only for exercises with nothing else, so precedence never has
    /// to break a tie — and a future import that overlaps the drawn art or the photographs
    /// should be caught here, not discovered as a silently hidden picture.
    @Test("frames never claim an id that has drawn art or photographs")
    func noOverlapWithOtherCatalogues() {
        for seedID in ExerciseFrameCatalog.seedIDs {
            #expect(ExerciseArtCatalog.frames(for: seedID) == nil, "\(seedID) has drawn art too")
            #expect(!ExercisePhotoCatalog.hasPhotos(for: seedID), "\(seedID) has photographs too")
        }
    }

    /// Aliases resolve before any catalogue is consulted, so an aliased exercise that later got
    /// frames of its own would still show its twin's picture. No such id exists today (the
    /// frames were generated for unaliased exercises only), and `ExerciseMediaTests` refuses an
    /// alias on anything with its own media — so the rule is pinned here on the data rather
    /// than exercised on a live example.
    @Test("no aliased exercise has frames of its own")
    func aliasesAndFramesAreDisjoint() {
        for (source, target) in ExerciseMediaAliases.aliases {
            #expect(!ExerciseFrameCatalog.hasFrames(for: source), "\(source) → \(target) but has frames")
            #expect(ExerciseHeroMedia.choice(for: source) != .frames(source))
        }
    }
}
