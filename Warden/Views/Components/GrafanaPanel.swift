import SwiftUI

/// A Grafana-style panel container with header bar and body.
struct GrafanaPanel<Content: View>: View {
    let title: String
    var icon: String? = nil
    var accentColor: Color = .grafanaBlue
    var headerTrailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(accentColor)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.grafanaTextSecondary)
                    .lineLimit(1)

                Spacer()

                if let headerTrailing {
                    headerTrailing
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.grafanaPanelHeaderBg)

            // Divider line
            Rectangle()
                .fill(Color.grafanaPanelBorder)
                .frame(height: 1)

            // Body
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.grafanaPanelBg)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.grafanaPanelBorder, lineWidth: 1)
        )
    }
}
