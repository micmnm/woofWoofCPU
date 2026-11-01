import SwiftUI

/// Recent values with a dashed limit line, so you can see why the dog barked. No line when `limit` is nil.
struct Sparkline: View {
    let values: [Double]
    let limit: Double?
    var color: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            let top = max(values.max() ?? 0, limit ?? 0) * 1.15
            guard top > 0 else { return }
            func y(_ value: Double) -> CGFloat { size.height - CGFloat(value / top) * size.height }

            if let limit {
                var limitLine = Path()
                limitLine.move(to: CGPoint(x: 0, y: y(limit)))
                limitLine.addLine(to: CGPoint(x: size.width, y: y(limit)))
                context.stroke(limitLine, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            guard values.count > 1 else { return }
            let step = size.width / CGFloat(values.count - 1)
            var line = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: CGFloat(index) * step, y: y(value))
                index == 0 ? line.move(to: point) : line.addLine(to: point)
            }
            context.stroke(line, with: .color(color), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}
