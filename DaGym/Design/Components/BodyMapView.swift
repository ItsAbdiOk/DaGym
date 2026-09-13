import GymCore
import SwiftUI

/// Abstract segmented body map: one component, three jobs (thumbnail,
/// live "muscles hit", recovery heatmap). Tapered stack of rounded
/// segments in a 100 × 140 box, not a silhouette.
struct BodyMapView: View {
    enum Mode {
        /// Four engagement steps of coral; 0 / nil = inert.
        case hit
        /// Fresh → spent on the 5-stop ramp; nil = inert.
        case recovery
    }

    enum Side {
        case front, back
    }

    var side: Side
    var mode: Mode = .hit
    /// 0…1 per muscle. Missing = inert.
    var intensity: [Muscle: Double] = [:]
    var onTap: ((Muscle) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(Preferences.self) private var preferences

    private struct Segment {
        let muscle: Muscle
        let rect: CGRect
        let radius: CGFloat
    }

    // Geometry copied from the design component (viewBox 0 0 100 140).
    private static let front: [Segment] = [
        Segment(muscle: .traps, rect: CGRect(x: 30, y: 0, width: 40, height: 12), radius: 5),
        Segment(muscle: .delts, rect: CGRect(x: 2, y: 16, width: 19, height: 20), radius: 6),
        Segment(muscle: .chest, rect: CGRect(x: 27, y: 16, width: 46, height: 20), radius: 6),
        Segment(muscle: .delts, rect: CGRect(x: 79, y: 16, width: 19, height: 20), radius: 6),
        Segment(muscle: .biceps, rect: CGRect(x: 4, y: 40, width: 16, height: 18), radius: 5),
        Segment(muscle: .abs, rect: CGRect(x: 30, y: 40, width: 40, height: 18), radius: 5),
        Segment(muscle: .biceps, rect: CGRect(x: 80, y: 40, width: 16, height: 18), radius: 5),
        Segment(muscle: .forearms, rect: CGRect(x: 6, y: 62, width: 14, height: 12), radius: 4),
        Segment(muscle: .obliques, rect: CGRect(x: 27, y: 62, width: 46, height: 12), radius: 5),
        Segment(muscle: .forearms, rect: CGRect(x: 80, y: 62, width: 14, height: 12), radius: 4),
        Segment(muscle: .quads, rect: CGRect(x: 22, y: 78, width: 56, height: 34), radius: 7),
        Segment(muscle: .calves, rect: CGRect(x: 32, y: 116, width: 36, height: 22), radius: 6)
    ]

    private static let back: [Segment] = [
        Segment(muscle: .traps, rect: CGRect(x: 24, y: 0, width: 52, height: 16), radius: 6),
        Segment(muscle: .delts, rect: CGRect(x: 2, y: 20, width: 19, height: 26), radius: 6),
        Segment(muscle: .lats, rect: CGRect(x: 27, y: 20, width: 46, height: 26), radius: 6),
        Segment(muscle: .delts, rect: CGRect(x: 79, y: 20, width: 19, height: 26), radius: 6),
        Segment(muscle: .triceps, rect: CGRect(x: 4, y: 50, width: 16, height: 16), radius: 5),
        Segment(muscle: .lowerBack, rect: CGRect(x: 30, y: 50, width: 40, height: 16), radius: 5),
        Segment(muscle: .triceps, rect: CGRect(x: 80, y: 50, width: 16, height: 16), radius: 5),
        Segment(muscle: .forearms, rect: CGRect(x: 6, y: 70, width: 14, height: 14), radius: 4),
        Segment(muscle: .glutes, rect: CGRect(x: 27, y: 70, width: 46, height: 14), radius: 5),
        Segment(muscle: .forearms, rect: CGRect(x: 80, y: 70, width: 14, height: 14), radius: 4),
        Segment(muscle: .hams, rect: CGRect(x: 22, y: 88, width: 56, height: 30), radius: 7),
        Segment(muscle: .calves, rect: CGRect(x: 32, y: 122, width: 36, height: 18), radius: 6)
    ]

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 100, geo.size.height / 140)
            let offset = CGSize(
                width: (geo.size.width - 100 * scale) / 2,
                height: (geo.size.height - 140 * scale) / 2
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    RoundedRectangle(cornerRadius: seg.radius * scale, style: .continuous)
                        .fill(color(for: seg.muscle))
                        .frame(width: seg.rect.width * scale, height: seg.rect.height * scale)
                        .offset(
                            x: seg.rect.minX * scale + offset.width,
                            y: seg.rect.minY * scale + offset.height
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?(seg.muscle) }
                }
            }
            .animation(DGMotion.aware(DGMotion.standard, reduceMotion: reduceMotion), value: intensity)
        }
        .aspectRatio(100 / 140, contentMode: .fit)
        .accessibilityLabel(accessibilityDescription)
    }

    private var segments: [Segment] {
        Self.adjusted(side == .front ? Self.front : Self.back, for: preferences.bodyFigure)
    }

    /// Nudges the shoulder (delts) and hip (quads/hams/glutes) segments a few units wider or
    /// narrower per `figure` — a subtle proportion difference, not a different drawing. Every
    /// other segment, and every `Muscle` region, is untouched.
    private static func adjusted(_ base: [Segment], for figure: Preferences.BodyFigure) -> [Segment] {
        guard figure != .neutral else { return base }
        let shoulderShift: CGFloat = figure == .male ? 2 : -2
        let hipShift: CGFloat = figure == .male ? -2 : 2
        return base.map { segment in
            switch segment.muscle {
            case .delts:
                let isLeftSide = segment.rect.minX < 50
                let dx = isLeftSide ? -shoulderShift : shoulderShift
                return Segment(
                    muscle: segment.muscle, rect: segment.rect.offsetBy(dx: dx, dy: 0), radius: segment.radius
                )
            case .quads, .hams, .glutes:
                return Segment(
                    muscle: segment.muscle, rect: segment.rect.insetBy(dx: -hipShift / 2, dy: 0),
                    radius: segment.radius
                )
            default:
                return segment
            }
        }
    }

    private func color(for muscle: Muscle) -> Color {
        guard let value = intensity[muscle], value > 0 else { return DGColor.bodyMapInert }
        switch mode {
        case .hit:
            let idx = Int((value * 3).rounded())
            return DGColor.hitSteps[min(3, max(0, idx))]
        case .recovery:
            let idx = Int((value * 4).rounded())
            return DGColor.recovery[min(4, max(0, idx))]
        }
    }

    private var accessibilityDescription: String { BodyMapAccessibility.label(intensity: intensity) }
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
            BodyMapView(side: .front, mode: mode, intensity: intensity)
                .accessibilityHidden(true)
            BodyMapView(side: .back, mode: mode, intensity: intensity)
                .accessibilityHidden(true)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BodyMapAccessibility.label(intensity: intensity))
    }
}

#Preview("Hit") {
    BodyMapPair(intensity: [.chest: 1, .delts: 0.6, .triceps: 0.4], height: 140)
        .padding()
        .background(DGColor.bgBase)
        .environment(Preferences())
}
