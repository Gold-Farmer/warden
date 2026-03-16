import SwiftUI

/// Grafana-style semi-circular gauge.
struct GaugeArcView: View {
    let fraction: Double
    let label: String
    let sublabel: String?
    var size: CGFloat = 120

    private let startAngle = Angle.degrees(135)
    private let endAngle = Angle.degrees(405) // 135 + 270
    private let lineWidth: CGFloat = 10

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background arc
                ArcShape(startAngle: startAngle, endAngle: endAngle)
                    .stroke(Color.grafanaPanelBorder, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: size, height: size * 0.65)

                // Value arc
                ArcShape(
                    startAngle: startAngle,
                    endAngle: Angle.degrees(135 + 270 * min(fraction, 1.0))
                )
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        startAngle: startAngle,
                        endAngle: Angle.degrees(135 + 270 * min(fraction, 1.0))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size * 0.65)

                // Center text
                VStack(spacing: 0) {
                    Spacer()
                    Text(label)
                        .font(.system(size: size * 0.22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forFraction(fraction))
                    if let sublabel {
                        Text(sublabel)
                            .font(.system(size: size * 0.09))
                            .foregroundStyle(.grafanaTextSecondary)
                    }
                }
                .frame(width: size, height: size * 0.65)
            }
            .frame(height: size * 0.65)
        }
    }

    private var gradientColors: [Color] {
        if fraction < 0.7 {
            return [.grafanaGreen, .grafanaGreen]
        } else if fraction < 0.9 {
            return [.grafanaGreen, .grafanaYellow]
        } else {
            return [.grafanaGreen, .grafanaYellow, .grafanaRed]
        }
    }
}

private struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY * 0.85)
        let radius = min(rect.width, rect.height * 1.5) / 2
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}
