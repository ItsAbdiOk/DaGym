import SwiftUI
import UIKit

/// Photographs of an exercise's start and end position (free-exercise-db, Unlicense / public
/// domain — see `DaGym/Resources/Acknowledgements.md`), shipped as plain HEIC files in the
/// bundle's `ExercisePhotos` folder and loaded by path via `ExercisePhotoStore`.
///
/// This is the second-choice hero: `ExerciseArtView`'s illustrated vector art wins where we have
/// it, and `ExerciseDetailView+Layout`'s `heroArt` picks between them. Shows the start position at
/// rest; `animated` cross-fades start → end → start on a loop so the movement reads as one rep.
///
/// With `accessibilityReduceMotion` on there is no loop and no cross-fade at all: both frames are
/// shown side by side, captioned Start and End, so the movement is still legible as a before/after
/// without anything moving. The driving task exits immediately in that case, so nothing keeps
/// re-rendering.
struct ExercisePhotoView: View {
    var seedID: String?
    /// Total width in points. Height follows the source photos' 3:2 frame.
    var width: CGFloat = 240
    var animated: Bool = false
    /// The exercise's display name, used only for the accessibility label.
    var exerciseName: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photos: ExercisePhotoPair?
    @State private var showingEnd = false

    /// Source photos are 850×567. Holding the box at that ratio whether or not the images have
    /// loaded keeps the hero from resizing under the scroll view mid-load.
    private static let aspectRatio: CGFloat = 850.0 / 567.0
    /// How long each position is held before cross-fading to the other.
    private static let holdDuration: TimeInterval = 1.1
    private static let fadeDuration: TimeInterval = 0.45

    var body: some View {
        content
            .task(id: seedID) { await load() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        if let photos {
            if animated, reduceMotion {
                sideBySide(photos)
            } else {
                crossfade(photos)
                    // Owned by SwiftUI: cancelled when the view goes away, restarted rather than
                    // stacked when it returns or when `animated`/Reduce Motion flips.
                    .task(id: motionID) { await runMotion() }
            }
        } else {
            placeholder
                .frame(width: width, height: width / Self.aspectRatio)
        }
    }

    /// Start and end stacked in a `ZStack`, cross-fading between them. Both frames are always
    /// mounted, so the fade never shows the background through a gap.
    private func crossfade(_ photos: ExercisePhotoPair) -> some View {
        ZStack {
            frame(photos.start).opacity(showingEnd ? 0 : 1)
            frame(photos.end).opacity(showingEnd ? 1 : 0)
        }
        .frame(width: width, height: width / Self.aspectRatio)
    }

    /// The Reduce Motion treatment: nothing animates, both positions are on screen at once.
    private func sideBySide(_ photos: ExercisePhotoPair) -> some View {
        let half = (width - DGSpace.s2) / 2
        return HStack(spacing: DGSpace.s2) {
            captioned(frame(photos.start), caption: "Start", width: half)
            captioned(frame(photos.end), caption: "End", width: half)
        }
        .frame(width: width)
    }

    private func captioned(_ image: some View, caption: String, width: CGFloat) -> some View {
        VStack(spacing: DGSpace.s1) {
            image.frame(width: width, height: width / Self.aspectRatio)
            Text(caption)
                .font(DGFont.footnote)
                .foregroundStyle(DGColor.ink4)
        }
        .accessibilityHidden(true)
    }

    private func frame(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .background(DGColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: DGRadius.lg, style: .continuous)
            .fill(DGColor.surface2)
            .overlay {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: width * 0.18, weight: .semibold))
                    .foregroundStyle(DGColor.ink4)
            }
            .accessibilityHidden(true)
    }

    /// Restarts the motion task whenever anything it depends on changes.
    private var motionID: String { "\(seedID ?? "")|\(animated)|\(reduceMotion)" }

    private func load() async {
        guard let seedID else {
            photos = nil
            return
        }
        photos = await ExercisePhotoStore.shared.photos(forSeedID: seedID)
    }

    private func runMotion() async {
        showingEnd = false
        guard animated, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.holdDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Self.fadeDuration)) { showingEnd.toggle() }
        }
    }

    /// Describes the movement, not the files. VoiceOver users get the same information a sighted
    /// user gets from watching the two positions alternate.
    private var accessibilityLabel: String {
        guard let seedID, ExercisePhotoCatalog.hasPhotos(for: seedID) else {
            return "Exercise photographs unavailable"
        }
        let name = exerciseName.map { " of \($0)" } ?? ""
        return "Photographs\(name) showing the start position and the end position of the movement"
    }
}

/// One exercise's two loaded frames. `Image` rather than `UIImage` so the value can cross the
/// actor boundary and be handed straight to SwiftUI.
struct ExercisePhotoPair: Sendable {
    var start: Image
    var end: Image
}

/// Loads the bundled exercise photographs off the main actor and keeps a deliberately small LRU
/// of decoded pairs.
///
/// The bound matters more here than it does for `ExerciseArtPathStore`: these are bitmaps, not
/// `Path`s. One 800 pt-wide frame costs roughly 1.7 MB decoded, so a pair is ~3.4 MB and this
/// cache tops out near 14 MB — hence four entries where the vector store keeps eight. Only
/// `ExerciseDetailView`'s hero draws these, so a miss costs one decode per exercise opened.
actor ExercisePhotoStore {
    static let shared = ExercisePhotoStore()

    /// How many exercises' decoded pairs to keep. Enough to make backing out of an exercise and
    /// straight back into it free, small enough that browsing the library never accumulates.
    private static let cacheLimit = 4

    private var cache: [String: ExercisePhotoPair] = [:]
    /// Least-recently-used first; `cache`'s eviction order.
    private var recentSeedIDs: [String] = []

    /// The start and end photographs for `seedID`, or `nil` when this exercise has none bundled
    /// (or its files are missing, which a test catches before it can ship).
    func photos(forSeedID seedID: String) async -> ExercisePhotoPair? {
        if let cached = cache[seedID] {
            touch(seedID)
            return cached
        }
        guard
            let names = ExercisePhotoCatalog.photoNames(for: seedID),
            let start = await Self.loadImage(named: names.start),
            let end = await Self.loadImage(named: names.end)
        else { return nil }
        let pair = ExercisePhotoPair(start: start, end: end)
        cache[seedID] = pair
        touch(seedID)
        evictIfNeeded()
        return pair
    }

    /// Whether both of `seedID`'s photo files are actually present in the bundle. Used by tests;
    /// callers should just ask for `photos(forSeedID:)`.
    nonisolated static func bundledURLs(forSeedID seedID: String) -> (start: URL, end: URL)? {
        guard
            let names = ExercisePhotoCatalog.photoNames(for: seedID),
            let start = url(named: names.start),
            let end = url(named: names.end)
        else { return nil }
        return (start, end)
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

    private static func url(named name: String) -> URL? {
        Bundle.main.url(
            forResource: name, withExtension: "heic",
            subdirectory: ExercisePhotoCatalog.bundleSubdirectory
        )
    }

    /// Decoded here, not on first draw: `UIImage(data:)` over a mapped HEIC defers the ~1.7 MB
    /// decode to the frame the hero first appears, on the main thread — which is what made the
    /// detail push hitch despite this being an actor. `byPreparingForDisplay` does that work
    /// now, off the main thread, so what gets cached is ready to draw.
    private static func loadImage(named name: String) async -> Image? {
        guard
            let url = url(named: name),
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
            ExercisePhotoView(
                seedID: "Barbell_Deadlift", width: 240, animated: true, exerciseName: "Barbell Deadlift"
            )
            ExercisePhotoView(
                seedID: "Ab_Roller", width: 240, animated: false, exerciseName: "Ab Roller"
            )
            ExercisePhotoView(
                seedID: "does-not-exist", width: 240, animated: true, exerciseName: "Nothing Here"
            )
        }
        .padding(DGSpace.s5)
    }
    .background(DGColor.bgBase)
}
