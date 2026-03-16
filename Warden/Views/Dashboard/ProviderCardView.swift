import SwiftUI

struct ProviderCardView: View {
    let account: Account
    let status: ProviderStatus?
    let error: Error?

    var body: some View {
        GrafanaPanel(
            title: account.label,
            icon: account.providerType.iconName,
            accentColor: account.providerType.grafanaColor,
            headerTrailing: headerTrailingView
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if let error {
                    errorBody(error)
                } else if let status {
                    configuredBody(status)
                } else {
                    unconfiguredBody
                }
            }
        }
        .frame(minHeight: 180)
    }

    // MARK: - Header trailing

    private var headerTrailingView: AnyView? {
        guard let status else { return nil }
        return AnyView(
            HStack(spacing: 8) {
                if let cost = status.totalMonthlyCost {
                    Text(Formatters.formatCost(cost))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.grafanaGreen)
                }
                StatusBadge(health: status.health, showLabel: false)
            }
        )
    }

    // MARK: - Configured

    private func configuredBody(_ status: ProviderStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Big stat number — total resources or cost
            HStack(alignment: .firstTextBaseline) {
                if let cost = status.totalMonthlyCost {
                    Text(Formatters.formatCost(cost))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forHealth(status.health))
                } else {
                    Text("\(status.resources.count)")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.grafanaTextPrimary)
                    Text("resources")
                        .font(.system(size: 11))
                        .foregroundStyle(.grafanaTextSecondary)
                }
                Spacer()
            }
            .padding(.top, 8)

            Spacer(minLength: 4)

            // Bar gauges for top resources
            ForEach(status.topResources) { resource in
                BarGaugeView(
                    fraction: resource.utilizationFraction,
                    label: resource.name,
                    valueText: usageText(resource),
                    height: 14,
                    style: .segmented
                )
            }

            if status.resources.isEmpty {
                Text("No resources detected")
                    .font(.system(size: 11))
                    .foregroundStyle(.grafanaTextDisabled)
            }

            // Footer timestamp
            HStack {
                Spacer()
                Text(Formatters.relativeDate.localizedString(for: status.fetchedAt, relativeTo: Date()))
                    .font(.system(size: 9))
                    .foregroundStyle(.grafanaTextDisabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Error

    private func errorBody(_ error: Error) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.grafanaRed)
            Text(error.localizedDescription)
                .font(.system(size: 11))
                .foregroundStyle(.grafanaRed.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Spacer()
        }
        .padding(12)
    }

    // MARK: - Unconfigured

    private var unconfiguredBody: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundStyle(.grafanaTextDisabled)
            Text("Not configured")
                .font(.system(size: 11))
                .foregroundStyle(.grafanaTextDisabled)
            Text("Add credentials in Settings")
                .font(.system(size: 10))
                .foregroundStyle(.grafanaTextDisabled.opacity(0.6))
            Spacer()
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func usageText(_ resource: ResourceQuota) -> String {
        let used = Formatters.formatUsage(resource.used, unit: resource.unit)
        if let limit = resource.limit {
            return "\(used) / \(Formatters.formatUsage(limit, unit: resource.unit))"
        }
        return used
    }
}
