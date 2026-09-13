import UIKit

/// Pure image downscaling for progress photos (plan.md §6.4) — no SwiftData, no store, just
/// `UIImage`/ImageIO math, so it's cheap to unit test with a generated image.
enum PhotoProcessor {
    /// Long edge of the full-size copy kept for storage/compare.
    static let storageLongEdge: CGFloat = 1600
    /// Long edge of the small copy used for grid thumbnails.
    static let thumbnailLongEdge: CGFloat = 300
    static let storageQuality: CGFloat = 0.85
    static let thumbnailQuality: CGFloat = 0.7

    struct ProcessedPhoto {
        let imageData: Data
        let thumbnailData: Data
        let imageSize: CGSize
        let thumbnailSize: CGSize
    }

    /// Downscales `image` (never upscales) to a 1600px-long-edge JPEG for storage plus a 300px
    /// thumbnail JPEG. Returns `nil` only if the source image or JPEG encoding is degenerate.
    static func process(_ image: UIImage) -> ProcessedPhoto? {
        guard let full = resized(image, longEdge: storageLongEdge),
              let thumbnail = resized(image, longEdge: thumbnailLongEdge),
              let imageData = full.jpegData(compressionQuality: storageQuality),
              let thumbnailData = thumbnail.jpegData(compressionQuality: thumbnailQuality) else {
            return nil
        }
        return ProcessedPhoto(
            imageData: imageData, thumbnailData: thumbnailData,
            imageSize: full.size, thumbnailSize: thumbnail.size
        )
    }

    /// Resizes `image` so its longer edge is at most `longEdge`, preserving aspect ratio.
    /// Images already smaller than `longEdge` are returned unscaled (never upscaled).
    static func resized(_ image: UIImage, longEdge: CGFloat) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, longEdge / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
}
