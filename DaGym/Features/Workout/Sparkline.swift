import SwiftUI

/// Tiny trend line drawn from raw values: a quiet ink stroke, the way the prototype draws it
/// beside the "LAST 3" numbers.
struct Sparkline: View {
    var values: [Double]

    var body: some View {
        GeometryReader { geo in
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let span = max(high - low, 0.001)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = values.count > 1
                        ? geo.size.width * CGFloat(index) / CGFloat(values.count - 1) : 0
                    let y = geo.size.height * (1 - CGFloat((value - low) / span))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(DGColor.ink4, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}
