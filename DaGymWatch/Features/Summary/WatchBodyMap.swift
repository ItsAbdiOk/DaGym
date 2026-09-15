import GymCore
import SwiftUI

/// The 28 × 48 pt body map on the summary: group fills only, no fibre detail at this size.
/// Draws the vendored MuscleMap male figure (the watch has no body-figure preference) with the
/// same 14-muscle mapping the phone uses (`BodyMapMuscleMapping`). Front and back side by side.
struct WatchBodyMap: View {
    var intensity: [Muscle: Double]
    var height: CGFloat = 48

    var body: some View {
        HStack(spacing: 6) {
            figure(side: .front)
            figure(side: .back)
        }
        .accessibilityHidden(true)
    }

    private func figure(side: BodySide) -> some View {
        let viewBox = BodyPathProvider.viewBox(gender: .male, side: side)
        let width = height * viewBox.size.width / viewBox.size.height
        return Canvas { context, size in
            let scale = min(size.width / viewBox.size.width, size.height / viewBox.size.height)
            let transform = CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: (size.width - viewBox.size.width * scale) / 2 - viewBox.origin.x * scale,
                ty: (size.height - viewBox.size.height * scale) / 2 - viewBox.origin.y * scale
            )
            for region in WatchBodyRegions.shared.regions(side: side) {
                context.fill(region.path.applying(transform), with: .color(fill(for: region.muscle)))
            }
        }
        .frame(width: width, height: height)
    }

    private func fill(for muscle: Muscle?) -> Color {
        guard let muscle, let value = intensity[muscle], value > 0 else { return WatchColor.cardRaised }
        return WatchColor.accent.opacity(0.35 + 0.65 * min(1, value))
    }
}

/// One merged path per muscle plus one inert path, parsed once per side — the watch's copy of
/// the phone's `BodyMapRegionCache`. `warm()` does the parse off the main actor at workout
/// start; the first Summary after Finish then finds both sides ready instead of building every
/// SVG path on the main thread while the screen waits.
@MainActor
final class WatchBodyRegions {
    static let shared = WatchBodyRegions()

    struct Region: Sendable {
        let muscle: Muscle?
        let path: Path
    }

    private var storage: [BodySide: [Region]] = [:]
    private var warming: Task<Void, Never>?

    func regions(side: BodySide) -> [Region] {
        if let cached = storage[side] { return cached }
        let built = Self.build(side: side)
        storage[side] = built
        return built
    }

    /// Parses both sides on a background task and caches them. A no-op once cached or while
    /// already warming.
    static func warm() { shared.startWarming() }

    private func startWarming() {
        guard storage.count < 2, warming == nil else { return }
        warming = Task.detached(priority: .utility) { [weak self] in
            let front = Self.build(side: .front)
            let back = Self.build(side: .back)
            await self?.store(front: front, back: back)
        }
    }

    private func store(front: [Region], back: [Region]) {
        if storage[.front] == nil { storage[.front] = front }
        if storage[.back] == nil { storage[.back] = back }
        warming = nil
    }

    nonisolated static func build(side: BodySide) -> [Region] {
        var inert = Path()
        var byMuscle: [Muscle: Path] = [:]
        for part in BodyPathProvider.paths(gender: .male, side: side) {
            let mapped = BodyMapMuscleMapping.muscle(for: part.slug)
            let muscle = mapped.flatMap { BodyMapMuscleMapping.isAddressable($0, on: side) ? $0 : nil }
            for svgPath in part.allPaths {
                let path = PathBuilder.buildPath(from: svgPath, scale: 1, offsetX: 0, offsetY: 0)
                if let muscle {
                    byMuscle[muscle, default: Path()].addPath(path)
                } else {
                    inert.addPath(path)
                }
            }
        }
        var built = [Region(muscle: nil, path: inert)]
        built += byMuscle.keys.sorted { $0.rawValue < $1.rawValue }.map {
            Region(muscle: $0, path: byMuscle[$0] ?? Path())
        }
        return built
    }
}
