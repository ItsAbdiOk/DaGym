import SwiftUI

/// Illustrated 3-frame artwork for an exercise (Bryl Lim, derived from Everkinetic, CC BY-SA
/// 4.0 — see `DaGym/Resources/ATTRIBUTION-ExerciseArt.txt`), rendered as `Path`s from raw SVG
/// path data (via `ExerciseArtPathStore`) and filled with our tint — no rasterised images
/// shipped. Falls back to a `RoutineGlyph`-style tinted chip when `seedID` has no matching art
/// in `ExerciseArtCatalog`, or while its paths are still loading.
///
/// `animated` cycles frame 1 → 2 → 3 → 2 on a gentle loop so the motion reads as one rep, not a
/// flicker. With `accessibilityReduceMotion` on there is no loop: the art cross-fades once from
/// frame 1 to frame 3 and then stays still, and the driving timeline is torn down so nothing
/// keeps re-rendering at display refresh rate.
struct ExerciseArtView: View {
    var seedID: String?
    var size: CGFloat = 44
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameIndex = 0
    @State private var paths: [Path]?
    /// When the reduce-motion one-shot cross-fade started, and whether it has finished.
    /// `nil`/`false` until the motion task runs; once finished the `TimelineView` is torn
    /// down so nothing re-evaluates at display refresh rate any more.
    @State private var crossfadeStart: Date?
    @State private var crossfadeFinished = false

    /// One playback step: 1 → 2 → 3 → 2 → (repeat), each held long enough to read as a
    /// deliberate rep rather than a flicker.
    private static let sequence = [1, 2, 3, 2]
    private static let stepDuration: TimeInterval = 0.55
    /// The reduce-motion one-shot cross-fade: frame 1 → frame 3, once, then still.
    private static let crossfadeDuration: TimeInterval = 4

    var body: some View {
        Group {
            if let paths {
                artwork(frames: paths)
            } else {
                ExerciseArtFallbackGlyph(size: size)
            }
        }
        .task(id: seedID) { await loadPaths() }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func artwork(frames: [Path]) -> some View {
        motionFrames(frames)
            // Owned by SwiftUI, so it is cancelled when the view goes away and restarted (not
            // stacked) when it comes back or when `animated`/Reduce Motion flips.
            .task(id: motionID) { await runMotion() }
    }

    @ViewBuilder
    private func motionFrames(_ frames: [Path]) -> some View {
        if !animated {
            frameShape(frames[0])
        } else if reduceMotion {
            // No looping motion: a slow one-shot cross-fade into frame 3, then a still frame —
            // the timeline is gone once it lands, so nothing keeps re-rendering.
            if crossfadeFinished {
                frameShape(frames[2])
            } else {
                TimelineView(.animation) { context in
                    let t = crossfadeProgress(at: context.date)
                    ZStack {
                        frameShape(frames[0]).opacity(1 - t)
                        frameShape(frames[2]).opacity(t)
                    }
                }
            }
        } else {
            frameShape(frames[Self.sequence[frameIndex] - 1])
        }
    }

    /// Restarts the motion task whenever anything it depends on changes.
    private var motionID: String { "\(seedID ?? "")|\(animated)|\(reduceMotion)" }

    private func frameShape(_ framePath: Path) -> some View {
        ExerciseArtShape(source: framePath)
            .fill(DGColor.ink2, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }

    private func loadPaths() async {
        guard let seedID, let slug = ExerciseArtCatalog.slug(for: seedID) else {
            paths = nil
            return
        }
        paths = await ExerciseArtPathStore.shared.frames(forSlug: slug)
    }

    /// Drives whichever motion the current settings call for, as a structured child of the
    /// view's own `.task(id:)` so SwiftUI cancels it on disappear — no detached ticker outlives
    /// the view, and re-appearing never stacks a second one.
    private func runMotion() async {
        guard animated else { return }
        guard !reduceMotion else {
            crossfadeFinished = false
            crossfadeStart = .now
            try? await Task.sleep(for: .seconds(Self.crossfadeDuration))
            guard !Task.isCancelled else { return }
            crossfadeFinished = true
            return
        }
        frameIndex = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.stepDuration))
            guard !Task.isCancelled else { return }
            frameIndex = (frameIndex + 1) % Self.sequence.count
        }
    }

    /// A slow one-shot cross-fade anchored to the moment the view appeared (not to the absolute
    /// clock), so it runs exactly once instead of restarting on a repeating modulus.
    private func crossfadeProgress(at date: Date) -> Double {
        guard let crossfadeStart else { return 0 }
        return min(1, max(0, date.timeIntervalSince(crossfadeStart) / Self.crossfadeDuration))
    }

    private var accessibilityLabel: String {
        guard let seedID, ExerciseArtCatalog.frames(for: seedID) != nil else {
            return "Exercise illustration unavailable"
        }
        return "Illustration demonstrating the movement"
    }
}

/// Scales a 512×512-viewBox `Path` (the source SVGs' native coordinate space) to fill whatever
/// rect SwiftUI gives it, so `ExerciseArtView` can request any display size without re-parsing.
private struct ExerciseArtShape: Shape {
    var source: Path

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 512
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return source.applying(transform)
    }
}

/// The fallback chip shown when an exercise has no illustrated art — mirrors `RoutineGlyph`'s
/// tinted rounded-square treatment so it reads as part of the same icon family.
private struct ExerciseArtFallbackGlyph: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(DGColor.ink3)
            .frame(width: size, height: size)
            .background(DGColor.surface2, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: DGSpace.s5) {
        HStack(spacing: DGSpace.s4) {
            ExerciseArtView(seedID: "Barbell_Squat", size: 64, animated: false)
            ExerciseArtView(seedID: "Barbell_Squat", size: 64, animated: true)
        }
        HStack(spacing: DGSpace.s4) {
            ExerciseArtView(seedID: "Barbell_Bench_Press_-_Medium_Grip", size: 96, animated: true)
            ExerciseArtView(seedID: "does-not-exist", size: 96, animated: true)
        }
    }
    .padding(DGSpace.s5)
    .background(DGColor.bgBase)
}
