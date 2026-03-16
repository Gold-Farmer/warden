import SwiftUI

/// Grafana-style stat panel — big centered value with title and optional spark area.
struct StatPanelView: View {
    let title: String
    let value: String
    let subtitle: String?
    var valueColor: Color = .grafanaTextPrimary
    var icon: String? = nil
    var accentColor: Color = .grafanaBlue

    var body: some View {
        GrafanaPanel(title: title, icon: icon, accentColor: accentColor) {
            VStack(spacing: 4) {
                Spacer()

                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.grafanaTextSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
