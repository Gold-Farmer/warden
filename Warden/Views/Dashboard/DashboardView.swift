import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var expandedRows: Set<String> = ["summary", "cloud", "ai"]

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
                if !cloudAccounts.isEmpty {
                    grafanaRow("cloud", title: "Cloud Infrastructure") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(cloudAccounts) { account in
                                NavigationLink(value: account) {
                                    ProviderCardView(
                                        account: account,
                                        status: viewModel.accountStatuses[account.id],
                                        error: viewModel.errors[account.id]
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // AI providers row
                if !aiAccounts.isEmpty {
                    grafanaRow("ai", title: "AI Services") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(aiAccounts) { account in
                                NavigationLink(value: account) {
                                    ProviderCardView(
                                        account: account,
                                        status: viewModel.accountStatuses[account.id],
                                        error: viewModel.errors[account.id]
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color.grafanaBg)
        .navigationTitle("Warden")
        .navigationDestination(for: Account.self) { account in
            ProviderDetailView(
                viewModel: ProviderDetailViewModel(
                    account: account,
                    registry: viewModel.registry
                ),
                dashboardStatus: viewModel.accountStatuses[account.id]
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

            // Account count badge
            Text("\(viewModel.configuredAccounts.count) accounts")
                .font(.system(size: 10))
                .foregroundStyle(.grafanaTextDisabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.grafanaPanelBg, in: RoundedRectangle(cornerRadius: 3))

            Spacer()

            // Overall health
            if !viewModel.accountStatuses.isEmpty {
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
                subtitle: "all accounts combined",
                valueColor: viewModel.totalMonthlyCost > 0 ? .grafanaGreen : .grafanaTextDisabled,
                icon: "dollarsign.circle",
                accentColor: .grafanaGreen
            )

            StatPanelView(
                title: "Active Accounts",
                value: "\(viewModel.configuredAccounts.count)",
                subtitle: "of \(viewModel.accountStore.accounts.count) configured",
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

    private var cloudAccounts: [Account] {
        viewModel.configuredAccounts.filter(\.providerType.isCloudProvider)
    }

    private var aiAccounts: [Account] {
        viewModel.configuredAccounts.filter(\.providerType.isAIProvider)
    }

    private var totalResources: Int {
        viewModel.accountStatuses.values.reduce(0) { $0 + $1.resources.count }
    }

    private var alertCount: Int {
        viewModel.accountStatuses.values
            .flatMap(\.resources)
            .filter { $0.utilizationLevel == .critical }
            .count
    }

    private var warningCount: Int {
        viewModel.accountStatuses.values
            .flatMap(\.resources)
            .filter { $0.utilizationLevel == .warning }
            .count
    }
}
