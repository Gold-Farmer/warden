import SwiftUI

struct MenuBarSummaryView: View {
    let viewModel: DashboardViewModel
    let onOpenDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Warden")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.grafanaTextPrimary)
                Spacer()
                StatusBadge(health: viewModel.overallHealth, showLabel: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()
                .background(Color.grafanaPanelBorder)

            // Cost summary
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Cost")
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaTextSecondary)
                    Text(Formatters.formatCost(viewModel.totalMonthlyCost))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.grafanaTextPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Accounts")
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaTextSecondary)
                    Text("\(viewModel.configuredAccounts.count)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.grafanaTextPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .background(Color.grafanaPanelBorder)

            // Account list
            if viewModel.configuredAccounts.isEmpty {
                Text("No accounts configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.grafanaTextDisabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.configuredAccounts) { account in
                        accountRow(account)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()
                .background(Color.grafanaPanelBorder)

            // Footer
            HStack {
                if let lastRefresh = viewModel.lastRefresh {
                    Text("Updated \(Formatters.relativeDate.localizedString(for: lastRefresh, relativeTo: Date()))")
                        .font(.system(size: 10))
                        .foregroundStyle(.grafanaTextDisabled)
                }
                Spacer()
                Button("Open Dashboard") {
                    onOpenDashboard()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.grafanaBlue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .background(Color.grafanaPanelBorder)

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit Warden")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.grafanaTextSecondary)
            .padding(.bottom, 4)
        }
        .frame(width: 280)
        .background(Color.grafanaPanelBg)
        .preferredColorScheme(.dark)
        .task {
            if viewModel.configuredAccounts.isEmpty && !viewModel.isLoading {
                await viewModel.loadCredentialsAndConfigure()
                await viewModel.refreshAll()
                viewModel.scheduler.start()
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        let status = viewModel.accountStatuses[account.id]
        let error = viewModel.errors[account.id]

        return HStack(spacing: 8) {
            Image(systemName: account.providerType.iconName)
                .font(.system(size: 10))
                .foregroundStyle(account.providerType.grafanaColor)
                .frame(width: 16)

            Text(account.label)
                .font(.system(size: 11))
                .foregroundStyle(.grafanaTextPrimary)
                .lineLimit(1)

            Spacer()

            if error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.grafanaRed)
            } else if let status {
                if let cost = status.totalMonthlyCost {
                    Text(Formatters.formatCost(cost))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.grafanaTextSecondary)
                }
                Circle()
                    .fill(Color.forHealth(status.health))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
