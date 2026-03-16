import SwiftUI

/// Minimal sparkline chart for inline use.
struct SparklineView: View {
    let dataPoints: [Double]
    var color: Color = .grafanaGreen
    var height: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            if dataPoints.count >= 2, let minVal = dataPoints.min(), let maxVal = dataPoints.max() {
                let range = maxVal - minVal
                let effectiveRange = range > 0 ? range : 1.0

                Path { path in
                    let stepX = geo.size.width / CGFloat(dataPoints.count - 1)
                    for (i, point) in dataPoints.enumerated() {
                        let x = stepX * CGFloat(i)
                        let y = geo.size.height * (1 - (point - minVal) / effectiveRange)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Fill area under the line
                Path { path in
                    let stepX = geo.size.width / CGFloat(dataPoints.count - 1)
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    for (i, point) in dataPoints.enumerated() {
                        let x = stepX * CGFloat(i)
                        let y = geo.size.height * (1 - (point - minVal) / effectiveRange)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(height: height)
    }
}
