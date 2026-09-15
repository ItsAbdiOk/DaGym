import CoreGraphics
import SwiftUI
import Testing
@testable import DaGym

/// The vendored MuscleMap PathBuilder used to flatten `a` commands to a chord; the bundled
/// body paths do contain arcs, so pin the cubic conversion's geometry.
@Suite("SVGArcConverter")
struct SVGArcConverterTests {

    /// Midpoint of each cubic should sit on the circle, not on the chord.
    @Test("quarter circle lands on the circle, not the chord")
    func quarterCircleStaysOnCircle() {
        let cubics = SVGArcConverter.cubics(
            from: CGPoint(x: 10, y: 0), to: CGPoint(x: 0, y: 10),
            rx: 10, ry: 10, xAxisRotation: 0, largeArc: false, sweep: true
        )
        #expect(cubics.count == 1)
        let cubic = cubics[0]
        #expect(cubic.end == CGPoint(x: 0, y: 10))
        // Bézier midpoint at t = 0.5.
        let mx = (10 + 3 * cubic.control1.x + 3 * cubic.control2.x + cubic.end.x) / 8
        let my = (0 + 3 * cubic.control1.y + 3 * cubic.control2.y + cubic.end.y) / 8
        let radius = (mx * mx + my * my).squareRoot()
        #expect(abs(radius - 10) < 0.03, "midpoint radius \(radius) should be ~10")
        // A chord would put the midpoint at radius ~7.07.
        #expect(radius > 9)
    }

    @Test("large arcs split into ≤90° slices")
    func largeArcSplits() {
        let cubics = SVGArcConverter.cubics(
            from: CGPoint(x: 10, y: 0), to: CGPoint(x: -10, y: 0),
            rx: 10, ry: 10, xAxisRotation: 0, largeArc: true, sweep: true
        )
        // 180° needs two slices; 270° would need three.
        #expect(cubics.count == 2)
        #expect(cubics.last?.end == CGPoint(x: -10, y: 0))
    }

    @Test("degenerate radius falls back to a straight segment")
    func zeroRadiusIsLine() {
        let cubics = SVGArcConverter.cubics(
            from: .zero, to: CGPoint(x: 5, y: 5),
            rx: 0, ry: 3, xAxisRotation: 0, largeArc: false, sweep: false
        )
        let end = CGPoint(x: 5, y: 5)
        #expect(cubics == [SVGArcConverter.Cubic(control1: .zero, control2: end, end: end)])
    }

    @Test("PathBuilder emits a curve for an arc command")
    func pathBuilderUsesCurves() {
        let path = PathBuilder.buildPath(from: "M10 0a10 10 0 0 1 -10 10", scale: 1, offsetX: 0, offsetY: 0)
        var sawCurve = false
        path.forEach { element in
            if case .curve = element { sawCurve = true }
        }
        #expect(sawCurve)
    }
}
