import GymCore
import SwiftUI

/// Body map: one component, three jobs (thumbnail, live "muscles hit", recovery heatmap).
/// Draws the real anatomical figure from the vendored MuscleMap package
/// (`DaGym/Vendor/MuscleMap`, MIT — see its `LICENSE`), tinting our 14 `GymCore.Muscle`
/// regions on top of an inert body silhouette. The mapping from MuscleMap's ~30 upstream
/// regions onto our 14 muscles lives in `BodyMapMuscleMapping`.
struct BodyMapView: View {
    enum Mode {
        /// Four engagement steps of coral; 0 / nil = inert.
        case hit
        /// Fresh → spent on the 5-stop ramp; nil = inert.
        case recovery
    }

    /// The vendored `BodySide` — the same two cases, so `BodyMapMuscleMapping` (which the watch
    /// app compiles without this view) can name a side without depending on it.
    typealias Side = BodySide

    /// A fixed width-for-height for thumbnail-sized maps. The figures' own aspect ratios differ
    /// (727:1280 male, 650:1450 female), so sizing a thumbnail by height alone makes its width —
    /// and everything laid out beside it — jump when the user switches `BodyFigure`. Call sites
    /// that only have a height box the map into this ratio instead; the figure still draws at
    /// its own proportions inside, just letterboxed.
    static let thumbnailAspectRatio: CGFloat = 100.0 / 140.0

    var side: Side
    var mode: Mode = .hit
    /// 0…1 per muscle. Missing = inert.
    var intensity: [Muscle: Double] = [:]
    var onTap: ((Muscle) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(Preferences.self) private var preferences

    /// One drawable region of the figure: `muscle` is nil for parts that aren't one of our
    /// 14 groups (head, hair, hands, feet, knees, ankles, neck) — those render as inert body.
    fileprivate struct Region {
        let muscle: Muscle?
        /// Unscaled path in MuscleMap's original SVG coordinate space; transformed to the
        /// view's own coordinate space at draw time.
        let path: Path
    }

    var body: some View {
        GeometryReader { geo in
            let gender = Self.gender(for: preferences.bodyFigure)
            let mmSide = self.mmSide
            let viewBox = BodyPathProvider.viewBox(gender: gender, side: mmSide)
            let scale = min(geo.size.width / viewBox.size.width, geo.size.height / viewBox.size.height)
            let offsetX = (geo.size.width - viewBox.size.width * scale) / 2 - viewBox.origin.x * scale
            let offsetY = (geo.size.height - viewBox.size.height * scale) / 2 - viewBox.origin.y * scale
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offsetX, ty: offsetY)

            let regions = BodyMapRegionCache.shared.regions(gender: gender, side: mmSide)
            ZStack(alignment: .topLeading) {
                ForEach(Array(regions.enumerated()), id: \.offset) { _, region in
                    let addressable = region.muscle.map {
                        BodyMapMuscleMapping.isAddressable($0, on: side)
                    } ?? false
                    let transformedPath = region.path.applying(transform)
                    let tappable = addressable && onTap != nil ? region.muscle : nil
                    transformedPath
                        .fill(fillColor(muscle: region.muscle, addressable: addressable))
                        .contentShape(transformedPath)
                        .onTapGesture {
                            if let tappable { onTap?(tappable) }
                        }
                        // Only addressable regions take a hit area. An inert one (a knee over
                        // the quads, the hands over the forearm, or `.adductors` — mapped to a
                        // back-only muscle — over the front thigh) is drawn *after* the muscle
                        // it overlaps, so leaving it hit-testable swallows that muscle's taps.
                        // With no `onTap` at all (thumbnails) nothing takes taps, so a row's
                        // own tap target keeps working over the whole thumbnail.
                        .allowsHitTesting(tappable != nil)
                }
            }
            .animation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion), value: intensity)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityLabel(accessibilityDescription)
    }

    private var mmSide: BodySide {
        switch side {
        case .front: .front
        case .back: .back
        }
    }

    /// The figure's own proportions (male and female source art have different aspect
    /// ratios), so the frame this view asks for tracks the active `BodyFigure`.
    private var aspectRatio: CGFloat {
        let gender = Self.gender(for: preferences.bodyFigure)
        let box = BodyPathProvider.viewBox(gender: gender, side: mmSide).size
        return box.width / box.height
    }

    /// MuscleMap ships male/female art only. `.neutral` has no androgynous figure to draw,
    /// so it falls back to the male figure — an arbitrary but documented choice; every
    /// `Muscle` region drawn is identical regardless, only proportions differ (see
    /// `BodyMapMuscleMapping`).
    private static func gender(for figure: Preferences.BodyFigure) -> BodyGender {
        switch figure {
        case .male, .neutral: .male
        case .female: .female
        }
    }

    private func fillColor(muscle: Muscle?, addressable: Bool) -> Color {
        guard addressable, let muscle else { return DGColor.bodyMapInert }
        return color(for: muscle)
    }

    private func color(for muscle: Muscle) -> Color {
        guard let value = intensity[muscle], value > 0 else { return DGColor.bodyMapInert }
        switch mode {
        case .hit:
            let idx = Int((value * 3).rounded())
            return DGColor.hitSteps[min(3, max(0, idx))]
        case .recovery:
            let idx = Int((value * 4).rounded())
            return recoveryRamp[min(4, max(0, idx))]
        }
    }

    /// `DGColor.recovery` unless the system's "Differentiate Without Color" setting or the
    /// user's own `Preferences.colorBlindHeatmaps` toggle asks for the colour-blind-safe ramp.
    private var recoveryRamp: [Color] {
        DGColor.recoveryRamp(
            differentiateWithoutColor: differentiateWithoutColor,
            colorBlindHeatmaps: preferences.colorBlindHeatmaps
        )
    }

    private var accessibilityDescription: String { BodyMapAccessibility.label(intensity: intensity) }
}

/// Parses and caches MuscleMap's SVG region data once per (gender, side), keyed off the
/// vendored `BodyPathProvider`. Paths are cached unscaled (`PathBuilder` with `scale: 1,
/// offsetX/Y: 0`) — cheap to re-transform per frame with a `CGAffineTransform`, unlike
/// re-parsing the underlying SVG path strings, which `BodyMapView` would otherwise do on
/// every body re-evaluation (it's used at thumbnail size in lists as well as full-screen).
@MainActor
private final class BodyMapRegionCache {
    static let shared = BodyMapRegionCache()

    private struct Key: Hashable {
        let gender: BodyGender
        let side: BodySide
    }

    private var storage: [Key: [BodyMapView.Region]] = [:]

    private init() {}

    /// One merged region per muscle, plus one for everything inert — never one per SVG part.
    ///
    /// Upstream draws a region *and* its sub-regions (chest over upper/lower chest, quads over
    /// inner/outer quad and hip flexors, knees over quads), and several of those collapse onto
    /// the same one of our 14 muscles. Filled separately at `bodyMapInert`'s 10% alpha, each
    /// overlap compounded — two layers read as 19%, three as 27% — which is what put dark
    /// blotches on the chest, abs, knees and inner thighs of an otherwise flat silhouette.
    /// Appending the subpaths into one `Path` and filling it once makes an overlap invisible
    /// (non-zero winding fills it exactly once), and incidentally cuts the figure from ~60
    /// filled shapes to at most 15.
    func regions(gender: BodyGender, side: BodySide) -> [BodyMapView.Region] {
        let key = Key(gender: gender, side: side)
        if let cached = storage[key] { return cached }

        // A muscle that isn't addressable on this side (hamstrings seen from the front) draws
        // in the inert colour too, so it has to join the inert path rather than sit on top of
        // it — otherwise it stacks exactly the same way the sub-regions did.
        let viewSide: BodyMapView.Side = side == .front ? .front : .back
        var inert = Path()
        var byMuscle: [Muscle: Path] = [:]
        for part in BodyPathProvider.paths(gender: gender, side: side) {
            let mapped = BodyMapMuscleMapping.muscle(for: part.slug)
            let muscle = mapped.flatMap {
                BodyMapMuscleMapping.isAddressable($0, on: viewSide) ? $0 : nil
            }
            for svgPath in part.allPaths {
                let path = PathBuilder.buildPath(from: svgPath, scale: 1, offsetX: 0, offsetY: 0)
                if let muscle {
                    byMuscle[muscle, default: Path()].addPath(path)
                } else {
                    inert.addPath(path)
                }
            }
        }

        // Inert first so tinted muscles sit on top of it, and muscles in a stable order so the
        // drawing does not reshuffle between renders.
        var built = [BodyMapView.Region(muscle: nil, path: inert)]
        built += byMuscle.keys.sorted { $0.rawValue < $1.rawValue }.map {
            BodyMapView.Region(muscle: $0, path: byMuscle[$0] ?? Path())
        }
        storage[key] = built
        return built
    }
}

/// Pure label-building for a body map's `intensity` — shared by the single-side
/// `BodyMapView` and the two-up `BodyMapPair`, and cheap to unit test.
enum BodyMapAccessibility {
    static func label(intensity: [Muscle: Double]) -> String {
        let named = intensity.filter { $0.value > 0 }.keys.map(\.displayName).sorted()
        return named.isEmpty ? "Body map, nothing highlighted" : "Body map: " + named.joined(separator: ", ")
    }
}

/// Front and back side by side, the way every card shows them.
struct BodyMapPair: View {
    var mode: BodyMapView.Mode = .hit
    var intensity: [Muscle: Double] = [:]
    var height: CGFloat = 44

    var body: some View {
        HStack(spacing: DGSpace.s1) {
            sideMap(.front)
            sideMap(.back)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BodyMapAccessibility.label(intensity: intensity))
    }

    /// Each side gets a fixed width for the given height, so the pair takes the same room —
    /// and the text beside it sits in the same place — whichever `BodyFigure` is active.
    private func sideMap(_ side: BodyMapView.Side) -> some View {
        BodyMapView(side: side, mode: mode, intensity: intensity)
            .frame(width: height * BodyMapView.thumbnailAspectRatio, height: height)
            .accessibilityHidden(true)
    }
}

#Preview("Hit") {
    BodyMapPair(intensity: [.chest: 1, .delts: 0.6, .triceps: 0.4], height: 140)
        .padding()
        .background(DGColor.bgBase)
        .environment(Preferences())
}
