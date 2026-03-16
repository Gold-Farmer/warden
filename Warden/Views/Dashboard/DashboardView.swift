import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var expandedRows: Set<String> = ["summary", "cloud", "ai", "unconfigured"]

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Top toolbar
                topToolbar

                // Summary stat row
                grafanaRow("summary", title: "Overview") {
                    summaryStatPanels
                }

                // Cloud providers row
                if !cloudProviders.isEmpty {
                    grafanaRow("cloud", title: "Cloud Infrastructure") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(cloudProviders) { provider in
                                NavigationLink(value: provider) {
                                    ProviderCardView(
                                        provider: provider,
                                        status: viewModel.providerStatuses[provider],
                                        error: viewModel.errors[provider]
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // AI providers row
                if !aiProviders.isEmpty {
                    grafanaRow("ai", title: "AI Services") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(aiProviders) { provider in
                                NavigationLink(value: provider) {
                                    ProviderCardView(
                                        provider: provider,
                                        status: viewModel.providerStatuses[provider],
                                        error: viewModel.errors[provider]
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Unconfigured row
                if !viewModel.unconfiguredProviders.isEmpty {
                    grafanaRow("unconfigured", title: "Not Configured") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(viewModel.unconfiguredProviders) { provider in
                                ProviderCardView(
                                    provider: provider,
                                    status: nil,
                                    error: nil
                                )
                                .opacity(0.5)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color.grafanaBg)
        .navigationTitle("Warden")
        .navigationDestination(for: Provider.self) { provider in
            ProviderDetailView(
                viewModel: ProviderDetailViewModel(
                    provider: provider,
                    registry: viewModel.registry
                ),
                dashboardStatus: viewModel.providerStatuses[provider]
            )
        }
        .task {
            await viewModel.loadCredentialsAndConfigure()
            await viewModel.refreshAll()
            viewModel.scheduler.start()
        }
    }

    // MARK: - Top Toolbar (Grafana-style)

    private var topToolbar: some View {
        HStack(spacing: 12) {
            // Dashboard icon + title
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.grafanaBlue)
                Text("Warden Dashboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.grafanaTextPrimary)
            }

            // Provider count badge
            Text("\(viewModel.configuredProviders.count)/\(Provider.allCases.count) providers")
                .font(.system(size: 10))
                .foregroundStyle(.grafanaTextDisabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.grafanaPanelBg, in: RoundedRectangle(cornerRadius: 3))

            Spacer()

            // Overall health
            if !viewModel.providerStatuses.isEmpty {
                StatusBadge(health: viewModel.overallHealth)
            }

            // Refresh
            RefreshButton(
                isLoading: viewModel.isLoading,
                lastRefresh: viewModel.lastRefresh
            ) {
                Task { await viewModel.refreshAll() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Grafana Row (collapsible section)

    private func grafanaRow<Content: View>(_ id: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row header — clickable to collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedRows.contains(id) {
                        expandedRows.remove(id)
                    } else {
                        expandedRows.insert(id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expandedRows.contains(id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.grafanaTextDisabled)
                        .frame(width: 12)

                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.grafanaTextSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    // Decorative line
                    Rectangle()
                        .fill(Color.grafanaPanelBorder)
                        .frame(height: 1)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            if expandedRows.contains(id) {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Summary Stat Panels

    private var summaryStatPanels: some View {
        HStack(spacing: 8) {
            StatPanelView(
                title: "Total Monthly Cost",
                value: Formatters.formatCost(viewModel.totalMonthlyCost),
                subtitle: "all providers combined",
                valueColor: viewModel.totalMonthlyCost > 0 ? .grafanaGreen : .grafanaTextDisabled,
                icon: "dollarsign.circle",
                accentColor: .grafanaGreen
            )

            StatPanelView(
                title: "Active Providers",
                value: "\(viewModel.configuredProviders.count)",
                subtitle: "of \(Provider.allCases.count) available",
                valueColor: .grafanaBlue,
                icon: "cloud.fill",
                accentColor: .grafanaBlue
            )

            StatPanelView(
                title: "Total Resources",
                value: "\(totalResources)",
                subtitle: "monitored",
                valueColor: .grafanaCyan,
                icon: "server.rack",
                accentColor: .grafanaCyan
            )

            StatPanelView(
                title: "Alerts",
                value: "\(alertCount)",
                subtitle: warningCount > 0 ? "\(warningCount) warnings" : "none",
                valueColor: alertCount > 0 ? .grafanaRed : .grafanaGreen,
                icon: "bell.fill",
                accentColor: alertCount > 0 ? .grafanaRed : .grafanaGreen
            )
        }
        .frame(height: 120)
    }

    // MARK: - Computed helpers

    private var cloudProviders: [Provider] {
        viewModel.configuredProviders.filter(\.isCloudProvider)
    }

    private var aiProviders: [Provider] {
        viewModel.configuredProviders.filter(\.isAIProvider)
    }

    private var totalResources: Int {
        viewModel.providerStatuses.values.reduce(0) { $0 + $1.resources.count }
    }

    private var alertCount: Int {
        viewModel.providerStatuses.values
            .flatMap(\.resources)
            .filter { $0.utilizationLevel == .critical }
            .count
    }

    private var warningCount: Int {
        viewModel.providerStatuses.values
            .flatMap(\.resources)
            .filter { $0.utilizationLevel == .warning }
            .count
    }
}
