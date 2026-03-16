import SwiftUI

struct ProviderDetailView: View {
    @Bindable var viewModel: ProviderDetailViewModel
    var dashboardStatus: ProviderStatus?

    private var status: ProviderStatus? {
        viewModel.status ?? dashboardStatus
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Provider header panel
                headerPanel

                // Gauges row (if resources with limits exist)
                if let status, !gaugeResources(status).isEmpty {
                    gaugeRow(status)
                }

                // Table panel with all resources
                if let status {
                    resourceTablePanel(status)
                } else {
                    emptyPanel
                }
            }
            .padding(8)
        }
        .background(Color.grafanaBg)
        .navigationTitle(viewModel.provider.displayName)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                RefreshButton(
                    isLoading: viewModel.isLoading,
                    lastRefresh: status?.fetchedAt
                ) {
                    Task { await viewModel.refresh() }
                }
            }
        }
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - Header

    private var headerPanel: some View {
        GrafanaPanel(
            title: viewModel.provider.displayName,
            icon: viewModel.provider.iconName,
            accentColor: viewModel.provider.grafanaColor,
            headerTrailing: AnyView(StatusBadge(health: status?.health ?? .unknown))
        ) {
            HStack(spacing: 24) {
                // Cost stat
                VStack(spacing: 2) {
                    Text(Formatters.formatCost(status?.totalMonthlyCost))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(status?.totalMonthlyCost != nil ? .grafanaGreen : .grafanaTextDisabled)
                    Text("Monthly Cost")
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaTextSecondary)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(Color.grafanaPanelBorder)
                    .frame(width: 1, height: 50)

                // Resources count
                VStack(spacing: 2) {
                    Text("\(status?.resources.count ?? 0)")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(.grafanaBlue)
                    Text("Resources")
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaTextSecondary)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(Color.grafanaPanelBorder)
                    .frame(width: 1, height: 50)

                // Health
                VStack(spacing: 2) {
                    StatusBadge(health: status?.health ?? .unknown)
                    Text("Status")
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .frame(height: 110)
    }

    // MARK: - Gauge Row

    private func gaugeRow(_ status: ProviderStatus) -> some View {
        HStack(spacing: 8) {
            ForEach(gaugeResources(status).prefix(4)) { resource in
                GrafanaPanel(title: resource.name, accentColor: viewModel.provider.grafanaColor) {
                    VStack {
                        Spacer()
                        GaugeArcView(
                            fraction: resource.utilizationFraction ?? 0,
                            label: percentText(resource),
                            sublabel: usageText(resource),
                            size: 100
                        )
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
        .frame(height: 140)
    }

    // MARK: - Resource Table

    private func resourceTablePanel(_ status: ProviderStatus) -> some View {
        GrafanaPanel(
            title: "Resources",
            icon: "list.bullet",
            accentColor: viewModel.provider.grafanaColor
        ) {
            VStack(spacing: 0) {
                // Table header
                HStack(spacing: 12) {
                    Color.clear.frame(width: 6) // dot placeholder
                    Text("NAME")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("USAGE")
                        .frame(width: 120, alignment: .center)
                    Text("VALUE")
                        .frame(width: 110, alignment: .trailing)
                    Text("COST")
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.grafanaTextDisabled)
                .textCase(.uppercase)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.grafanaPanelHeaderBg)

                Rectangle()
                    .fill(Color.grafanaPanelBorder)
                    .frame(height: 1)

                // Grouped resources
                ForEach(status.resourcesByCategory, id: \.category) { group in
                    // Category header
                    HStack {
                        Text(group.category.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.grafanaTextDisabled)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Rectangle()
                            .fill(Color.grafanaPanelBorder)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    ForEach(group.resources) { resource in
                        ResourceRowView(resource: resource)
                    }

                    Rectangle()
                        .fill(Color.grafanaPanelBorder.opacity(0.5))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyPanel: some View {
        GrafanaPanel(title: "No Data", icon: "chart.bar.xaxis") {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .font(.largeTitle)
                    .foregroundStyle(.grafanaTextDisabled)
                Text("Configure credentials in Settings")
                    .font(.system(size: 12))
                    .foregroundStyle(.grafanaTextDisabled)
                Spacer()
            }
            .padding()
        }
        .frame(height: 200)
    }

    // MARK: - Helpers

    private func gaugeResources(_ status: ProviderStatus) -> [ResourceQuota] {
        status.resources.filter { $0.utilizationFraction != nil }
    }

    private func percentText(_ resource: ResourceQuota) -> String {
        guard let fraction = resource.utilizationFraction else { return "—" }
        return "\(Int(fraction * 100))%"
    }

    private func usageText(_ resource: ResourceQuota) -> String {
        let used = Formatters.formatUsage(resource.used, unit: resource.unit)
        if let limit = resource.limit {
            return "\(used) / \(Formatters.formatUsage(limit, unit: resource.unit))"
        }
        return used
    }
}
