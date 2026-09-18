import GymCore
import ImageIO
import SwiftUI
import UIKit

/// A small picture of a gym station for the profile editor and the custom-exercise machine
/// picker: the start frame of `Machine.representativeExerciseSeedID`'s bundled photograph
/// (free-exercise-db, public domain), or the station's SF Symbol when nothing bundled shows it.
struct MachineThumbnailView: View {
    var machine: Machine
    var size: CGFloat = 44

    @State private var image: Image?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DGColor.surface2)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: machine.symbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
        .task(id: machine) {
            guard let seedID = machine.representativeExerciseSeedID else {
                image = nil
                return
            }
            image = await MachineThumbnailStore.shared.thumbnail(forSeedID: seedID)
        }
    }
}

/// Decodes station thumbnails at thumbnail size and keeps every one — thirty-odd images at
/// ~120 px are a few hundred kilobytes, so unlike `ExercisePhotoStore` (full 850 px frames,
/// four at a time) nothing needs evicting, and a list of every station scrolls without
/// re-decoding.
actor MachineThumbnailStore {
    static let shared = MachineThumbnailStore()

    /// Pixels on the long edge. Twice the 44 pt row thumbnail at 3×, rounded.
    static let maxPixelSize = 264

    /// Bounded: exercise rows now use this store too, and a scroll through the whole library
    /// would otherwise keep every ~280 KB thumbnail. 160 entries is a few screens either side
    /// of wherever the lifter is, about 45 MB.
    static let cacheLimit = 160

    private var cache: [String: Image] = [:]
    /// Least-recently-used first.
    private var order: [String] = []

    /// The start frame of `seedID`'s bundled photograph at thumbnail size.
    func thumbnail(forSeedID seedID: String) -> Image? {
        guard let urls = ExercisePhotoStore.bundledURLs(forSeedID: seedID) else { return nil }
        return thumbnail(at: urls.start)
    }

    /// The middle frame of `seedID`'s generated line-art at thumbnail size — the position that
    /// best tells the movement apart in a 44 pt square.
    func frameThumbnail(forSeedID seedID: String) -> Image? {
        guard let urls = ExerciseFrameStore.bundledURLs(forSeedID: seedID) else { return nil }
        return thumbnail(at: urls[urls.count / 2])
    }

    /// One cache for both kinds, keyed by file path so a photo and a frame set for the same
    /// seedID (which never happens, but would otherwise collide) stay distinct.
    private func thumbnail(at url: URL) -> Image? {
        let key = url.path
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        guard let image = Self.downsampled(url, maxPixelSize: Self.maxPixelSize) else { return nil }
        let result = Image(uiImage: image)
        cache[key] = result
        touch(key)
        while order.count > Self.cacheLimit, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
        return result
    }

    private func touch(_ key: String) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }

    /// ImageIO's thumbnail path decodes straight to the target size instead of decoding the
    /// full frame and scaling it.
    nonisolated static func downsampled(_ url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
