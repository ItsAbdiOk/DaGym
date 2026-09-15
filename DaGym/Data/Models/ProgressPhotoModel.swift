import Foundation
import SwiftData

/// One progress photo: a pose shot with an optional bodyweight snapshot. Lives in its own
/// local-only `ModelConfiguration` (see `ModelContainer+DaGym.swift`) so "don't sync photos"
/// (plan.md §5, §6.4) can be enforced per-container rather than per-record — CloudKit sync is a
/// whole-store setting, so the only way to keep photos off iCloud while everything else syncs is
/// a second, `cloudKitDatabase: .none` store.
///
/// CloudKit-legal even though this store never syncs today: every property is optional or has a
/// default, no `@Attribute(.unique)`, no non-optional relationships — so turning sync on for this
/// store later (if that ever changes) costs nothing.
@Model
final class ProgressPhotoModel {
    var id = UUID()
    var date = Date()
    /// "front", "side" or "back" — see `ProgressPhotoPose`.
    var pose: String = "front"
    /// Full-size JPEG, downscaled to a 1600px long edge. `.externalStorage` keeps large blobs out
    /// of the store file itself (plan.md §5).
    @Attribute(.externalStorage) var imageData: Data?
    /// Small JPEG (~300px long edge) for grid thumbnails, so the grid never decodes full photos.
    @Attribute(.externalStorage) var thumbnailData: Data?
    var bodyweightKg: Double?
    var notes: String = ""

    init(
        id: UUID = UUID(), date: Date = Date(), pose: String = "front",
        imageData: Data? = nil, thumbnailData: Data? = nil,
        bodyweightKg: Double? = nil, notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.pose = pose
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.bodyweightKg = bodyweightKg
        self.notes = notes
    }
}

/// The three poses `ProgressPhotosView` segments by — plain strings on the model (CloudKit-legal,
/// no enum-backed attribute needed) with this as the typed, UI-facing wrapper.
enum ProgressPhotoPose: String, CaseIterable, Identifiable {
    case front, side, back

    var id: String { rawValue }

    var label: String {
        switch self {
        case .front: "Front"
        case .side: "Side"
        case .back: "Back"
        }
    }
}
