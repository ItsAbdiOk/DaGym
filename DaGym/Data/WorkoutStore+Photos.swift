import Foundation
import SwiftData
import UIKit

/// One progress photo, for `ProgressPhotosView`/`PhotoCompareView`. `photos(pose:)` leaves
/// `imageData` nil so the grid only ever loads thumbnails; `latestPhoto(pose:)` and `photo(id:)`
/// carry the full-size bytes for compare/full view.
struct ProgressPhotoInfo: Identifiable, Hashable {
    var id: UUID
    var date: Date
    var pose: ProgressPhotoPose
    var thumbnailData: Data?
    var imageData: Data?
    var bodyweightKg: Double?
    var notes: String
}

extension WorkoutStore {
    /// Downscales `data` (via `PhotoProcessor`) and saves it as a new progress photo. Returns
    /// `nil` without writing anything if `data` isn't decodable as an image or the photo store
    /// is unavailable.
    @discardableResult
    func addPhoto(
        image data: Data, pose: ProgressPhotoPose, date: Date = Date(), bodyweightKg: Double? = nil
    ) -> ProgressPhotoModel? {
        guard let image = UIImage(data: data), let processed = PhotoProcessor.process(image) else {
            return nil
        }
        return addPhoto(processed: processed, pose: pose, date: date, bodyweightKg: bodyweightKg)
    }

    /// Saves an already-processed photo — the capture flow decodes and resizes off the main
    /// actor (`PhotoProcessor.process` is ~300–500 ms for a camera JPEG) and hands the result
    /// here. Returns `nil` without writing when the photo store is unavailable.
    @discardableResult
    func addPhoto(
        processed: PhotoProcessor.ProcessedPhoto, pose: ProgressPhotoPose, date: Date = Date(),
        bodyweightKg: Double? = nil
    ) -> ProgressPhotoModel? {
        guard let photoContext else { return nil }
        let model = ProgressPhotoModel(
            date: date, pose: pose.rawValue, imageData: processed.imageData,
            thumbnailData: processed.thumbnailData, bodyweightKg: bodyweightKg
        )
        photoContext.insert(model)
        savePhotos()
        return model
    }

    /// All photos for one pose, newest first, for `ProgressPhotosView`'s grid — thumbnails only.
    func photos(pose: ProgressPhotoPose) -> [ProgressPhotoInfo] {
        let rawPose = pose.rawValue
        let predicate = #Predicate<ProgressPhotoModel> { $0.pose == rawPose }
        let descriptor = FetchDescriptor<ProgressPhotoModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return ((try? photoContext?.fetch(descriptor)) ?? []).compactMap { Self.photoInfo($0, full: false) }
    }

    /// One photo with its full-size bytes, for compare/full view.
    func photo(id: UUID) -> ProgressPhotoInfo? {
        var descriptor = FetchDescriptor<ProgressPhotoModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return ((try? photoContext?.fetch(descriptor))?.first).flatMap { Self.photoInfo($0, full: true) }
    }

    /// The most recent photo for a pose — used both by `BodyView`'s summary card and by
    /// `PhotoCaptureView` for the ghost-overlay reference shot.
    func latestPhoto(pose: ProgressPhotoPose) -> ProgressPhotoInfo? {
        let rawPose = pose.rawValue
        var descriptor = FetchDescriptor<ProgressPhotoModel>(
            predicate: #Predicate<ProgressPhotoModel> { $0.pose == rawPose },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return ((try? photoContext?.fetch(descriptor))?.first).flatMap { Self.photoInfo($0, full: true) }
    }

    func deletePhoto(id: UUID) {
        var descriptor = FetchDescriptor<ProgressPhotoModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let photoContext, let model = (try? photoContext.fetch(descriptor))?.first else { return }
        photoContext.delete(model)
        savePhotos()
    }

    private static func photoInfo(_ model: ProgressPhotoModel, full: Bool) -> ProgressPhotoInfo? {
        guard let pose = ProgressPhotoPose(rawValue: model.pose) else { return nil }
        return ProgressPhotoInfo(
            id: model.id, date: model.date, pose: pose, thumbnailData: model.thumbnailData,
            imageData: full ? model.imageData : nil, bodyweightKg: model.bodyweightKg, notes: model.notes
        )
    }
}
