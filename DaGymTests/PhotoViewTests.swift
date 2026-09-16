import Foundation
import SwiftData
import Testing
import UIKit

@testable import DaGym

@MainActor
@Suite("Progress photo screens")
struct PhotoViewTests {
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeImageData() throws -> Data {
        // Scale 1 so the decoded image's point size equals its pixel size; the default renderer
        // scale follows the (simulator) screen and `UIImage(data:)` always reads back at 1×.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    @Test("deleting a photo removes its row from the grid and bumps the change token")
    func deleteRemovesRow() throws {
        let store = try makeStore()
        let data = try makeImageData()
        let earlier = Date().addingTimeInterval(-60)
        let keep = try #require(store.addPhoto(image: data, pose: .front, date: earlier))
        let doomed = try #require(store.addPhoto(image: data, pose: .front))
        #expect(store.photos(pose: .front).count == 2)
        let token = store.changeToken

        store.deletePhoto(id: doomed.id)

        let remaining = store.photos(pose: .front)
        #expect(remaining.map(\.id) == [keep.id])
        #expect(store.photo(id: doomed.id) == nil)
        #expect(store.changeToken > token)
    }

    @Test("the compare pair is fetched at full size while the grid stays thumbnail-only")
    func compareFetchesFullBytes() throws {
        let store = try makeStore()
        let photo = try #require(store.addPhoto(image: try makeImageData(), pose: .side))

        let gridInfo = try #require(store.photos(pose: .side).first)
        #expect(gridInfo.imageData == nil)
        #expect(gridInfo.thumbnailData != nil)

        let full = try #require(store.photo(id: photo.id))
        #expect(full.imageData != nil)
    }

    @Test("the Settings lock toggle round-trips through Preferences")
    func lockPhotosRoundTrips() throws {
        let suite = makeSuite(#function)
        let first = Preferences(suite: suite)
        #expect(first.lockPhotos == false)

        first.lockPhotos = true
        #expect(Preferences(suite: suite).lockPhotos == true)

        first.lockPhotos = false
        #expect(Preferences(suite: suite).lockPhotos == false)
    }

    @Test("the bodyweight goal set from the Body tab round-trips and clears")
    func bodyweightGoalRoundTrips() throws {
        let suite = makeSuite(#function)
        let first = Preferences(suite: suite)
        #expect(first.bodyweightGoalKg == nil)

        first.bodyweightGoalKg = 80
        #expect(Preferences(suite: suite).bodyweightGoalKg == 80)

        first.bodyweightGoalKg = nil
        #expect(Preferences(suite: suite).bodyweightGoalKg == nil)
    }

    // MARK: - Decode-once caches (compare slider, Body thumbnails, capture review)

    @Test("PhotoDecoder decodes JPEG bytes to a display-ready image and rejects junk")
    func decoderRoundTrips() async throws {
        let data = try makeImageData()
        let sync = try #require(PhotoDecoder.decodeNow(data))
        #expect(sync.size == CGSize(width: 200, height: 200))

        let optionalData: Data? = data
        let decodedOffMain = await PhotoDecoder.decodeForDisplay(optionalData)
        let offMain = try #require(decodedOffMain)
        #expect(offMain.size == CGSize(width: 200, height: 200))

        let junk: UIImage? = PhotoDecoder.decodeNow(Data([0, 1, 2, 3]))
        #expect(junk == nil)
        let missing: Data? = nil
        let decodedMissing = await PhotoDecoder.decodeForDisplay(missing)
        #expect(decodedMissing == nil)
    }

    @Test("prepareForDisplay keeps a capture's pixel size")
    func prepareKeepsSize() async throws {
        let image = try #require(UIImage(data: try makeImageData()))
        let prepared = await PhotoDecoder.prepareForDisplay(image)
        #expect(prepared.size == image.size)
    }

    @Test("a pre-processed capture saves at storage size without shrinking again")
    func preProcessedCaptureSavesOnce() throws {
        let store = try makeStore()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 4000))
        let large = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 4000))
        }
        // `PhotoCaptureView.save` runs this step on a detached task, then hands the bytes on.
        let processed = try #require(PhotoProcessor.process(large))
        #expect(processed.imageSize.height == PhotoProcessor.storageLongEdge)

        let saved = try #require(store.addPhoto(image: processed.imageData, pose: .back, bodyweightKg: 80))
        let stored = try #require(store.photo(id: saved.id))
        let storedData = try #require(stored.imageData)
        let storedImage = try #require(UIImage(data: storedData))
        #expect(storedImage.size.height == PhotoProcessor.storageLongEdge)
        #expect(stored.bodyweightKg == 80)
        #expect(stored.thumbnailData != nil)
    }
}
