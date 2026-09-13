import SwiftUI

/// Three glass depths only — thin (24), regular (32), thick (46). Every glass
/// surface carries a hairline plus an inset specular top edge; that edge is
/// what sells the material. Glass is for chrome floating over content, never
/// a reading surface.
enum GlassDepth {
    case thin, regular, thick

    var fillOpacity: Double {
        switch self {
        case .thin: 0.05
        case .regular: 0.07
        case .thick: 0.11
        }
    }
}

struct DGGlassModifier<S: InsettableShape>: ViewModifier {
    let depth: GlassDepth
    let shape: S
    let tint: Color?
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let fill: Color = scheme == .dark
            ? .white.opacity(depth.fillOpacity)
            : .white.opacity(0.66)
        content
            .background {
                shape.fill(fill)
                    .glassEffect(.regular.tint(tint ?? .clear), in: shape)
            }
            .overlay {
                shape.strokeBorder(DGColor.hairline, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                // Specular top edge.
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(scheme == .dark ? 0.22 : 0.9), .clear],
                            startPoint: .top, endPoint: .center
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func dgGlass<S: InsettableShape>(
        _ depth: GlassDepth = .regular, in shape: S, tint: Color? = nil
    ) -> some View {
        modifier(DGGlassModifier(depth: depth, shape: shape, tint: tint))
    }

    func dgGlass(
        _ depth: GlassDepth = .regular, radius: CGFloat = DGRadius.lg, tint: Color? = nil
    ) -> some View {
        dgGlass(depth, in: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint)
    }
}

/// Resting, opaque card (elev-1). For reading surfaces.
struct DGCardModifier: ViewModifier {
    var radius: CGFloat = DGRadius.lg
    var fill: Color = DGColor.surface1
    var stroke: Color = DGColor.hairline
    var padding: CGFloat = DGSpace.s5

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 1, y: 1)
    }
}

extension View {
    func dgCard(
        radius: CGFloat = DGRadius.lg,
        fill: Color = DGColor.surface1,
        stroke: Color = DGColor.hairline,
        padding: CGFloat = DGSpace.s5
    ) -> some View {
        modifier(DGCardModifier(radius: radius, fill: fill, stroke: stroke, padding: padding))
    }
}

/// The ambient three-stop wash the glass refracts: ember top-right, violet
/// mid-left, green bottom. Sits under the scroll view, never per card.
struct AmbientWash: View {
    /// 0…1 — more ember as session volume climbs.
    var heat: Double = 0.5
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let base = DGColor.bgBase
        let ember = DGColor.coral.opacity(dark ? 0.16 + 0.18 * heat : 0.10 + 0.14 * heat)
        let violet = DGColor.aiViolet.opacity(dark ? 0.12 : 0.08)
        let green = DGColor.success.opacity(dark ? 0.10 : 0.06)
        ZStack {
            base
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    .clear, .clear, ember,
                    violet, .clear, .clear,
                    .clear, green, .clear
                ]
            )
        }
        .ignoresSafeArea()
    }
}
