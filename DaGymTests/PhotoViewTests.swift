import Foundation
import SwiftData
import Testing
import UIKit

@testable import DaGym

@MainActor
@Suite("Progress photo screens")
struct PhotoViewTests {
    private func makeStore() throws -> WorkoutStore {
        let container = try ModelContainer.dagym(inMemory: true)
        return WorkoutStore(context: ModelContext(container))
    }

    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeImageData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
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
}
