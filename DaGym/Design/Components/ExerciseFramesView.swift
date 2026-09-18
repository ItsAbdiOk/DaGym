import SwiftUI
import UIKit

/// Generated 3-frame line-art for an exercise — start, middle and end of the movement, drawn in
/// the style of the Bryl Lim illustrations, generated for DaGym and owned by the project (see
/// `DaGym/Resources/ATTRIBUTION-ExerciseFrames.txt`). Shipped as grayscale HEIC files in the
/// bundle's `ExerciseFrames` folder and loaded by path via `ExerciseFrameStore`.
///
/// This is the hero's second choice: `ExerciseArtView`'s vector art wins where we have it, these
/// frames cover exercises that had neither art nor photographs, and `ExerciseHeroMedia` picks.
/// Sits on a paper-white square like the drawn art so the card reads the same either way.
///
/// `animated` cross-fades start → mid → end → mid → start on a slow loop so the movement reads
/// as one rep. With `accessibilityReduceMotion` on there is no loop and no cross-fade: the
/// three frames are shown side by side, captioned Start · Mid · End, so the movement is still
/// legible without anything moving — the same treatment `ExercisePhotoView` gives its pair.
struct ExerciseFramesView: View {
    var seedID: String?
    /// The square the art is fitted into, in points — the hero card's 160 pt slot.
    var size: CGFloat = 160
    var animated: Bool = false
    /// The exercise's display name, used only for the accessibility label.
    var exerciseName: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [Image]?
    @State private var step = 0

    /// One playback step through the loaded frames: 0 → 1 → 2 → 1 → (repeat).
    private static let sequence = [0, 1, 2, 1]
    /// How long each position is held before cross-fading to the next.
    private static let holdDuration: TimeInterval = 0.9
    private static let fadeDuration: TimeInterval = 0.4
    /// Source frames are portrait (~485×640), so three fit side by side at this ratio.
    private static let aspectRatio: CGFloat = 485.0 / 640.0

    var body: some View {
        content
            .task(id: seedID) { await load() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        if let frames, frames.count == ExerciseFrameCatalog.frameCount {
            if animated, reduceMotion {
                sideBySide(frames)
            } else {
                crossfade(frames)
                    // Owned by SwiftUI: cancelled when the view goes away, restarted rather than
                    // stacked when it returns or when `animated`/Reduce Motion flips.
                    .task(id: motionID) { await runMotion() }
            }
        } else {
            placeholder
        }
    }

    /// All three frames mounted in a `ZStack`, only the current step visible, so a fade never
    /// shows the paper through a gap.
    private func crossfade(_ frames: [Image]) -> some View {
        let current = Self.sequence[step]
        return ZStack {
            ForEach(Array(frames.enumerated()), id: \.offset) { index, image in
                image.resizable().scaledToFit().opacity(index == current ? 1 : 0)
            }
        }
        .padding(DGSpace.s2)
        .frame(width: size, height: size)
        .background(Color.white, in: RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
    }

    /// The Reduce Motion treatment: nothing animates, all three positions are on screen at once.
    private func sideBySide(_ frames: [Image]) -> some View {
        let captions = ["Start", "Mid", "End"]
        let each = (size - DGSpace.s2 * 2) / 3
        return HStack(spacing: DGSpace.s2) {
            ForEach(Array(frames.enumerated()), id: \.offset) { index, image in
                VStack(spacing: DGSpace.s1) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: each, height: each / Self.aspectRatio)
                        .background(
                            Color.white, in: RoundedRectangle(cornerRadius: DGRadius.md, style: .continuous)
                        )
                    Text(captions[index])
                        .font(DGFont.footnote)
                        .foregroundStyle(DGColor.ink4)
                }
            }
        }
        .frame(width: size)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
            .fill(DGColor.surface2)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: size * 0.18, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .accessibilityHidden(true)
    }

    /// Restarts the motion task whenever anything it depends on changes.
    private var motionID: String { "\(seedID ?? "")|\(animated)|\(reduceMotion)" }

    private func load() async {
        guard let seedID else {
            frames = nil
            return
        }
        frames = await ExerciseFrameStore.shared.frames(forSeedID: seedID)
    }

    private func runMotion() async {
        step = 0
        guard animated, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.holdDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Self.fadeDuration)) {
                step = (step + 1) % Self.sequence.count
            }
        }
    }

    /// Describes the movement, not the files.
    private var accessibilityLabel: String {
        guard let seedID, ExerciseFrameCatalog.hasFrames(for: seedID) else {
            return "Exercise illustration unavailable"
        }
        let name = exerciseName.map { " of \($0)" } ?? ""
        return "Illustration\(name) showing the start, middle and end of the movement"
    }
}

/// Loads an exercise's bundled generated frames off the main actor and keeps a small LRU of
/// decoded sets — the same shape as `ExercisePhotoStore`, sized for its own bitmaps: a 485×640
/// grayscale frame is ~0.3 MB decoded, so a set of three is under 1 MB and four sets stay under
/// 4 MB. Only `ExerciseDetailView`'s hero draws these; rows go through `MachineThumbnailStore`.
actor ExerciseFrameStore {
    static let shared = ExerciseFrameStore()

    /// How many exercises' decoded sets to keep: enough that backing out of an exercise and
    /// straight back in is free, small enough that browsing never accumulates.
    private static let cacheLimit = 4

    private var cache: [String: [Image]] = [:]
    /// Least-recently-used first; `cache`'s eviction order.
    private var recentSeedIDs: [String] = []

    /// The frames for `seedID` in movement order, or `nil` when this exercise has none bundled
    /// (or a file is missing, which a test catches before it can ship).
    func frames(forSeedID seedID: String) async -> [Image]? {
        if let cached = cache[seedID] {
            touch(seedID)
            return cached
        }
        guard let urls = Self.bundledURLs(forSeedID: seedID) else { return nil }
        var images: [Image] = []
        for url in urls {
            guard let image = await Self.loadImage(at: url) else { return nil }
            images.append(image)
        }
        cache[seedID] = images
        touch(seedID)
        evictIfNeeded()
        return images
    }

    /// Every frame file for `seedID`, or `nil` unless all of them are present in the bundle.
    /// Used by tests and the thumbnail store; callers should just ask for `frames(forSeedID:)`.
    nonisolated static func bundledURLs(forSeedID seedID: String) -> [URL]? {
        guard let names = ExerciseFrameCatalog.frameNames(for: seedID) else { return nil }
        let urls = names.compactMap { name in
            Bundle.main.url(
                forResource: name, withExtension: "heic",
                subdirectory: ExerciseFrameCatalog.bundleSubdirectory
            )
        }
        return urls.count == names.count ? urls : nil
    }

    private func touch(_ seedID: String) {
        recentSeedIDs.removeAll { $0 == seedID }
        recentSeedIDs.append(seedID)
    }

    private func evictIfNeeded() {
        while recentSeedIDs.count > Self.cacheLimit {
            cache.removeValue(forKey: recentSeedIDs.removeFirst())
        }
    }

    /// Decoded here, off the main thread, so what gets cached is ready to draw on the frame the
    /// hero first appears (the lesson from `ExercisePhotoStore`).
    private static func loadImage(at url: URL) async -> Image? {
        guard
            let data = try? Data(contentsOf: url, options: .mappedIfSafe),
            let image = UIImage(data: data)
        else { return nil }
        let prepared = await image.byPreparingForDisplay() ?? image
        return Image(uiImage: prepared)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: DGSpace.s5) {
            ExerciseFramesView(seedID: "3D_lunge_warmup", animated: true, exerciseName: "3D lunge warmup")
            ExerciseFramesView(seedID: "3D_lunge_warmup", animated: false)
            ExerciseFramesView(seedID: "does-not-exist", animated: true, exerciseName: "Nothing Here")
        }
        .padding(DGSpace.s5)
    }
    .background(DGColor.bgBase)
}
