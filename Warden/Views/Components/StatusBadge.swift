import SwiftUI

struct StatusBadge: View {
    let health: ProviderStatus.Health
    var showLabel: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            // Pulsing dot for critical
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: health == .critical ? 4 : 0)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.4), lineWidth: health == .critical ? 2 : 0)
                        .scaleEffect(health == .critical ? 1.8 : 1)
                        .opacity(health == .critical ? 0 : 1)
                        .animation(
                            health == .critical
                                ? .easeOut(duration: 1.2).repeatForever(autoreverses: false)
                                : .default,
                            value: health
                        )
                )

            if showLabel {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
                    .textCase(.uppercase)
            }
        }
    }

    private var color: Color {
        switch health {
        case .healthy: .grafanaGreen
        case .warning: .grafanaYellow
        case .critical: .grafanaRed
        case .unknown: .grafanaTextDisabled
        }
    }

    private var label: String {
        switch health {
        case .healthy: "OK"
        case .warning: "WARN"
        case .critical: "CRIT"
        case .unknown: "N/A"
        }
    }
}
