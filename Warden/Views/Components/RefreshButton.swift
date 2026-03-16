import SwiftUI

struct RefreshButton: View {
    let isLoading: Bool
    let lastRefresh: Date?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.grafanaTextSecondary)
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(
                        isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                        value: isLoading
                    )

                if let lastRefresh {
                    Text(Formatters.relativeDate.localizedString(for: lastRefresh, relativeTo: Date()))
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaTextDisabled)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.grafanaPanelBg, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.grafanaPanelBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .keyboardShortcut("r", modifiers: .command)
    }
}
