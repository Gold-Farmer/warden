import SwiftUI

/// Thin usage bar — still available for compact inline use.
/// For full Grafana-style, prefer BarGaugeView.
struct UsageBarView: View {
    let fraction: Double?
    let label: String?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.grafanaPanelBorder)

                if let fraction, fraction > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.forFraction(fraction))
                        .frame(width: max(geo.size.width * fraction, 4))
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let fraction {
            return "\(label ?? "Usage"): \(Int(fraction * 100)) percent"
        }
        return "\(label ?? "Usage"): unknown"
    }
}
