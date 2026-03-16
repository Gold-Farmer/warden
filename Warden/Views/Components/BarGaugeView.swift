import SwiftUI

/// Grafana-style horizontal bar gauge with segmented LED look.
struct BarGaugeView: View {
    let fraction: Double?
    let label: String
    let valueText: String
    var height: CGFloat = 24
    var showLabel: Bool = true
    var style: BarGaugeStyle = .segmented

    enum BarGaugeStyle {
        case segmented  // LED-strip look
        case gradient   // Smooth gradient fill
        case basic      // Solid color
    }

    private let segmentCount = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showLabel {
                HStack {
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.grafanaTextSecondary)
                    Spacer()
                    Text(valueText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.grafanaTextPrimary)
                }
            }

            GeometryReader { geo in
                switch style {
                case .segmented:
                    segmentedBar(width: geo.size.width)
                case .gradient:
                    gradientBar(width: geo.size.width)
                case .basic:
                    basicBar(width: geo.size.width)
                }
            }
            .frame(height: height)
        }
    }

    // MARK: - Segmented (LED strip)

    private func segmentedBar(width: CGFloat) -> some View {
        let gap: CGFloat = 2
        let segWidth = (width - CGFloat(segmentCount - 1) * gap) / CGFloat(segmentCount)
        let filledCount = Int(Double(segmentCount) * min(fraction ?? 0, 1.0))

        return HStack(spacing: gap) {
            ForEach(0..<segmentCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < filledCount ? colorForSegment(i) : Color.grafanaPanelBorder)
                    .frame(width: max(segWidth, 2))
            }
        }
    }

    private func colorForSegment(_ index: Int) -> Color {
        let position = Double(index) / Double(segmentCount)
        if position < 0.6 { return .grafanaGreen }
        if position < 0.8 { return .grafanaYellow }
        return .grafanaRed
    }

    // MARK: - Gradient

    private func gradientBar(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.grafanaPanelBorder)

            if let fraction, fraction > 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.grafanaThresholdGradient)
                    .frame(width: max(width * fraction, 6))
            }
        }
    }

    // MARK: - Basic

    private func basicBar(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.grafanaPanelBorder)

            if let fraction, fraction > 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.forFraction(fraction))
                    .frame(width: max(width * fraction, 6))
            }
        }
    }
}
