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

/// The reading card from the redesign prototype: frosted white over the ambient wash
/// (`rgba(255,255,255,.66)`, a bright half-point edge, a soft warm drop shadow). Dark mode is
/// the same recipe on a low white fill so the wash still shows through.
struct DGCardModifier: ViewModifier {
    var radius: CGFloat = DGRadius.lg
    var fill: Color = DGColor.surface1
    var stroke: Color = DGColor.hairline
    var padding: CGFloat = DGSpace.s5
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let cardFill: Color = fill == DGColor.surface1
            ? .white.opacity(dark ? 0.07 : 0.66) : fill
        let edge: Color = stroke == DGColor.hairline
            ? .white.opacity(dark ? 0.12 : 0.9) : stroke
        content
            .padding(padding)
            .background {
                shape.fill(cardFill)
                    .background(.ultraThinMaterial, in: shape)
            }
            .overlay { shape.strokeBorder(edge, lineWidth: 0.5) }
            .shadow(color: Color(hex: 0x3C2814).opacity(dark ? 0.35 : 0.10), radius: 17, y: 7)
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

/// The ambient wash the cards frost over — three blurred blobs from the prototype: the accent
/// top-right, a cool teal mid-left and a pale green bottom-right. Sits under the scroll view,
/// never per card.
struct AmbientWash: View {
    /// 0…1 — more accent as session volume climbs.
    var heat: Double = 0.5
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                DGColor.bgBase
                Circle()
                    .fill(DGColor.coral)
                    .frame(width: 340, height: 340)
                    .blur(radius: 90)
                    .opacity(dark ? 0.22 + 0.12 * heat : 0.24 + 0.12 * heat)
                    .position(x: width + 80, y: 60)
                Circle()
                    .fill(Color(hex: 0x9FD3DA))
                    .frame(width: 300, height: 300)
                    .blur(radius: 95)
                    .opacity(dark ? 0.16 : 0.5)
                    .position(x: 20, y: 480)
                Circle()
                    .fill(Color(hex: 0xCBDDB4))
                    .frame(width: 300, height: 300)
                    .blur(radius: 95)
                    .opacity(dark ? 0.14 : 0.45)
                    .position(x: width + 90, y: proxy.size.height + 80)
            }
            // Three 90-pt blurs would otherwise be re-filtered every frame of a tab switch or a
            // scroll; rasterised once per size they're a single texture.
            .drawingGroup()
        }
        .ignoresSafeArea()
    }
}
