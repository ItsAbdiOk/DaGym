import Foundation
import SwiftData
import Testing
import UIKit

@testable import DaGym

@MainActor
@Suite("Photo store availability")
struct PhotoStoreTests {
    private func makeImageData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    @Test("the grid list carries thumbnails only; photo(id:) and latestPhoto carry the full image")
    func gridListLeavesImageDataNil() throws {
        let store = try makeStore()
        let saved = try #require(store.addPhoto(image: try makeImageData(), pose: .front))

        let listed = try #require(store.photos(pose: .front).first)
        #expect(listed.imageData == nil)
        #expect(listed.thumbnailData != nil)
        #expect(store.photo(id: saved.id)?.imageData != nil)
        #expect(store.latestPhoto(pose: .front)?.imageData != nil)
    }

    @Test("with no photo context, photo calls are safe no-ops")
    func nilPhotoContextIsSafe() throws {
        let container = try ModelContainer.dagym(inMemory: true)
        let store = WorkoutStore(context: ModelContext(container), photoContext: nil)

        #expect(store.addPhoto(image: try makeImageData(), pose: .front) == nil)
        #expect(store.photos(pose: .front).isEmpty)
        #expect(store.latestPhoto(pose: .front) == nil)
        #expect(store.photo(id: UUID()) == nil)
        store.deletePhoto(id: UUID())
        store.savePhotos()
        #expect(!store.context.hasChanges)
    }
}
