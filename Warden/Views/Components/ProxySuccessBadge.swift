import SwiftUI

/// Animated success badge shown when proxy test passes.
struct ProxySuccessBadge: View {
    @State private var appear = false
    @State private var checkmarkTrim: CGFloat = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var textOpacity: Double = 0
    @State private var shimmer: CGFloat = -1

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                // Pulsing ring
                Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .scaleEffect(ringScale)

                // Filled circle
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)
                    .scaleEffect(appear ? 1 : 0)

                // Animated checkmark
                CheckmarkShape()
                    .trim(from: 0, to: checkmarkTrim)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 10, height: 10)
            }

            Text("Connected")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
                .opacity(textOpacity)

            // Shimmer overlay on text
            Text("Connected")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.6), .clear],
                        startPoint: UnitPoint(x: shimmer - 0.3, y: 0.5),
                        endPoint: UnitPoint(x: shimmer + 0.3, y: 0.5)
                    )
                )
                .opacity(textOpacity)
                .mask(
                    Text("Connected")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                )
        }
        .onAppear {
            // Circle pop
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                appear = true
                ringScale = 1.0
            }
            // Checkmark draw
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                checkmarkTrim = 1
            }
            // Text fade in
            withAnimation(.easeIn(duration: 0.3).delay(0.4)) {
                textOpacity = 1
            }
            // Shimmer
            withAnimation(.easeInOut(duration: 0.8).delay(0.6)) {
                shimmer = 2
            }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.1, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.85))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.15))
        return path
    }
}
