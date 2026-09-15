// DaGym addition to the vendored MuscleMap sources (MIT, see DaGym/Vendor/MuscleMap/LICENSE).
// Upstream PathBuilder flattens SVG `A`/`a` commands to a straight chord; the bundled body
// paths contain small corner arcs, so this converts an endpoint-parameterised arc into one
// cubic Bézier per ≤90° slice, following the SVG 1.1 implementation notes (§F.6.5/F.6.6).

import CoreGraphics

struct SVGArcConverter {

    struct Cubic: Equatable {
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    /// Returns the cubic segments approximating the arc from `start` to `end`. A degenerate
    /// arc (zero radius, or start == end) returns a single straight segment so callers never
    /// have to special-case it.
    static func cubics(
        from start: CGPoint,
        to end: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        xAxisRotation: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) -> [Cubic] {
        if start == end { return [] }
        var rx = abs(rx)
        var ry = abs(ry)
        if rx == 0 || ry == 0 {
            return [Cubic(control1: start, control2: end, end: end)]
        }

        let phi = xAxisRotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // F.6.5.1 — move to the ellipse's own coordinate frame.
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // F.6.6 — scale radii up if the endpoints cannot be joined by the given ellipse.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let root = sqrt(lambda)
            rx *= root
            ry *= root
        }

        // F.6.5.2 — centre in the rotated frame.
        let rx2 = rx * rx
        let ry2 = ry * ry
        let numerator = max(0, rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p)
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        var coefficient = denominator == 0 ? 0 : sqrt(numerator / denominator)
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * -(ry * x1p / rx)

        // F.6.5.3 — centre back in user space.
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        // F.6.5.4 — start angle and sweep.
        let startVector = CGPoint(x: (x1p - cxp) / rx, y: (y1p - cyp) / ry)
        let endVector = CGPoint(x: (-x1p - cxp) / rx, y: (-y1p - cyp) / ry)
        let theta1 = angle(from: CGPoint(x: 1, y: 0), to: startVector)
        var deltaTheta = angle(from: startVector, to: endVector)
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        // Split into ≤90° slices; each becomes one cubic with the standard k = 4/3·tan(δ/4).
        let sliceCount = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2) - 1e-9)))
        let sliceAngle = deltaTheta / CGFloat(sliceCount)
        let kappa = 4 / 3 * tan(sliceAngle / 4)

        func point(at theta: CGFloat) -> CGPoint {
            let x = rx * cos(theta)
            let y = ry * sin(theta)
            return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
        func derivative(at theta: CGFloat) -> CGPoint {
            let x = -rx * sin(theta)
            let y = ry * cos(theta)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }

        var result: [Cubic] = []
        result.reserveCapacity(sliceCount)
        var theta = theta1
        var from = start
        for index in 0..<sliceCount {
            let next = theta + sliceAngle
            let isLast = index == sliceCount - 1
            let to = isLast ? end : point(at: next)
            let d1 = derivative(at: theta)
            let d2 = derivative(at: next)
            let control1 = CGPoint(x: from.x + kappa * d1.x, y: from.y + kappa * d1.y)
            let control2 = CGPoint(x: to.x - kappa * d2.x, y: to.y - kappa * d2.y)
            result.append(Cubic(control1: control1, control2: control2, end: to))
            theta = next
            from = to
        }
        return result
    }

    private static func angle(from u: CGPoint, to v: CGPoint) -> CGFloat {
        let dot = u.x * v.x + u.y * v.y
        let length = sqrt((u.x * u.x + u.y * u.y) * (v.x * v.x + v.y * v.y))
        guard length > 0 else { return 0 }
        let cosine = min(1, max(-1, dot / length))
        let sign: CGFloat = (u.x * v.y - u.y * v.x) < 0 ? -1 : 1
        return sign * acos(cosine)
    }
}
