import Foundation
import SwiftData
import UIKit

/// One progress photo, for `ProgressPhotosView`/`PhotoCompareView`. `imageData` is only fetched
/// when actually needed (compare/full view); the grid uses `thumbnailData`.
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
    /// `nil` without writing anything if `data` isn't decodable as an image.
    @discardableResult
    func addPhoto(
        image data: Data, pose: ProgressPhotoPose, date: Date = Date(), bodyweightKg: Double? = nil
    ) -> ProgressPhotoModel? {
        guard let image = UIImage(data: data), let processed = PhotoProcessor.process(image) else {
            return nil
        }
        let model = ProgressPhotoModel(
            date: date, pose: pose.rawValue, imageData: processed.imageData,
            thumbnailData: processed.thumbnailData, bodyweightKg: bodyweightKg
        )
        context.insert(model)
        save()
        return model
    }

    /// All photos for one pose, newest first, for `ProgressPhotosView`'s grid.
    func photos(pose: ProgressPhotoPose) -> [ProgressPhotoInfo] {
        let rawPose = pose.rawValue
        let predicate = #Predicate<ProgressPhotoModel> { $0.pose == rawPose }
        let descriptor = FetchDescriptor<ProgressPhotoModel>(
            predicate: predicate, sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).compactMap(Self.photoInfo)
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
        return ((try? context.fetch(descriptor))?.first).flatMap(Self.photoInfo)
    }

    func deletePhoto(id: UUID) {
        var descriptor = FetchDescriptor<ProgressPhotoModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let model = (try? context.fetch(descriptor))?.first else { return }
        context.delete(model)
        save()
    }

    private static func photoInfo(_ model: ProgressPhotoModel) -> ProgressPhotoInfo? {
        guard let pose = ProgressPhotoPose(rawValue: model.pose) else { return nil }
        return ProgressPhotoInfo(
            id: model.id, date: model.date, pose: pose, thumbnailData: model.thumbnailData,
            imageData: model.imageData, bodyweightKg: model.bodyweightKg, notes: model.notes
        )
    }
}
