import SwiftUI

/// Illustrated 3-frame artwork for an exercise (Bryl Lim, derived from Everkinetic, CC BY-SA
/// 4.0 — see `DaGym/Resources/ATTRIBUTION-ExerciseArt.txt`), rendered as `Path`s from raw SVG
/// path data (via `ExerciseArtPathStore`) and filled with our tint — no rasterised images
/// shipped. Falls back to a `RoutineGlyph`-style tinted chip when `seedID` has no matching art
/// in `ExerciseArtCatalog`, or while its paths are still loading.
///
/// `animated` cycles frame 1 → 2 → 3 → 2 on a gentle loop so the motion reads as one rep, not a
/// flicker. With `accessibilityReduceMotion` on, it shows frame 1 only — no looping motion.
struct ExerciseArtView: View {
    var seedID: String?
    var size: CGFloat = 44
    var animated: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameIndex = 0
    @State private var paths: [Path]?

    /// One playback step: 1 → 2 → 3 → 2 → (repeat), each held long enough to read as a
    /// deliberate rep rather than a flicker.
    private static let sequence = [1, 2, 3, 2]
    private static let stepDuration: TimeInterval = 0.55

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
        if reduceMotion {
            // No looping motion: frame 1 at rest, or a slow one-shot cross-fade into frame 3
            // when asked to animate, per the reduce-motion contract (no repeating movement).
            if animated {
                TimelineView(.animation) { context in
                    let t = crossfadeProgress(since: context.date)
                    ZStack {
                        frameShape(frames[0]).opacity(1 - t)
                        frameShape(frames[2]).opacity(t)
                    }
                }
            } else {
                frameShape(frames[0])
            }
        } else if animated {
            frameShape(frames[Self.sequence[frameIndex] - 1])
                .onAppear(perform: startLoop)
        } else {
            frameShape(frames[0])
        }
    }

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

    private func startLoop() {
        guard animated, !reduceMotion else { return }
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.stepDuration))
                guard animated else { return }
                frameIndex = (frameIndex + 1) % Self.sequence.count
            }
        }
    }

    /// A slow 4-second one-shot cross-fade, held on frame 3, for the reduce-motion + animated case.
    private func crossfadeProgress(since referenceDate: Date) -> Double {
        let elapsed = referenceDate.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8)
        return min(1, max(0, elapsed / 4))
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
