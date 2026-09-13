import Foundation
import SwiftData
import Testing
import UIKit

@testable import DaGym

@MainActor
@Suite("WorkoutStore progress photos")
struct WorkoutStorePhotoTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    /// A tiny solid-color JPEG, standing in for a captured photo.
    private func makeImageData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        return try #require(image.jpegData(compressionQuality: 0.9))
    }

    @Test("the container builds with both the main and the local-only photo configuration")
    func containerBuildsWithBothConfigurations() throws {
        _ = try ModelContainer.dagym(inMemory: true)
    }

    @Test("addPhoto persists a downscaled photo, listable by pose")
    func addPhotoPersistsAndLists() throws {
        let store = try makeStore()
        let data = try makeImageData()

        let saved = try #require(store.addPhoto(image: data, pose: .front, bodyweightKg: 81.4))
        #expect(saved.pose == "front")

        let listed = store.photos(pose: .front)
        #expect(listed.count == 1)
        #expect(listed[0].bodyweightKg == 81.4)
        #expect(listed[0].thumbnailData != nil)
    }

    @Test("addPhoto with undecodable data does not persist anything")
    func addPhotoRejectsGarbageData() throws {
        let store = try makeStore()
        let saved = store.addPhoto(image: Data([0x00, 0x01, 0x02]), pose: .front)
        #expect(saved == nil)
        #expect(store.photos(pose: .front).isEmpty)
    }

    @Test("photos(pose:) only returns that pose, newest first")
    func photosFilterByPoseNewestFirst() throws {
        let store = try makeStore()
        let data = try makeImageData()
        let older = Date().addingTimeInterval(-86_400)
        store.addPhoto(image: data, pose: .front, date: older)
        store.addPhoto(image: data, pose: .side, date: Date())
        store.addPhoto(image: data, pose: .front, date: Date())

        let front = store.photos(pose: .front)
        #expect(front.count == 2)
        #expect(front[0].date > front[1].date)
        #expect(store.photos(pose: .side).count == 1)
    }

    @Test("latestPhoto(pose:) returns the newest photo for that pose only")
    func latestPhotoPerPose() throws {
        let store = try makeStore()
        let data = try makeImageData()
        let older = Date().addingTimeInterval(-86_400)
        store.addPhoto(image: data, pose: .front, date: older)
        let newest = store.addPhoto(image: data, pose: .front, date: Date())

        #expect(store.latestPhoto(pose: .front)?.id == newest?.id)
        #expect(store.latestPhoto(pose: .back) == nil)
    }

    @Test("deletePhoto removes it from subsequent listings")
    func deletePhotoRemoves() throws {
        let store = try makeStore()
        let data = try makeImageData()
        let saved = try #require(store.addPhoto(image: data, pose: .front))

        store.deletePhoto(id: saved.id)

        #expect(store.photos(pose: .front).isEmpty)
    }
}
