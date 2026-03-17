import SwiftUI

/// A single actionable insight surfaced by the rule engine.
struct Insight: Identifiable {
    let id = UUID()
    let priority: Priority
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String?
    let accountId: UUID?

    enum Priority: Int, Comparable {
        case info = 0
        case notice = 1
        case warning = 2
        case critical = 3

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

/// Rule engine that evaluates all account data and produces prioritized insights.
enum InsightEngine {

    static func evaluate(
        statuses: [UUID: ProviderStatus],
        errors: [UUID: Error],
        accounts: [Account],
        totalCost: Decimal
    ) -> [Insight] {
        var insights: [Insight] = []

        // --- Connection errors (highest urgency alongside critical) ---
        for account in accounts {
            if let error = errors[account.id] {
                insights.append(Insight(
                    priority: .critical,
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .grafanaRed,
                    title: "\(account.label) connection failed",
                    detail: error.localizedDescription,
                    accountId: account.id
                ))
            }
        }

        // --- Critical resources (≥90% utilization) ---
        for account in accounts {
            guard let status = statuses[account.id] else { continue }
            let criticals = status.resources.filter { $0.utilizationLevel == .critical }
            for resource in criticals {
                let pct = resource.utilizationFraction.map { Int($0 * 100) } ?? 0
                insights.append(Insight(
                    priority: .critical,
                    icon: "flame.fill",
                    iconColor: .grafanaRed,
                    title: "\(resource.name) at \(pct)%",
                    detail: "\(account.label) · \(resource.category.rawValue)",
                    accountId: account.id
                ))
            }
        }

        // --- Warning resources (70-89% utilization) ---
        for account in accounts {
            guard let status = statuses[account.id] else { continue }
            let warnings = status.resources.filter { $0.utilizationLevel == .warning }
            for resource in warnings {
                let pct = resource.utilizationFraction.map { Int($0 * 100) } ?? 0
                insights.append(Insight(
                    priority: .warning,
                    icon: "exclamationmark.circle.fill",
                    iconColor: .grafanaYellow,
                    title: "\(resource.name) at \(pct)%",
                    detail: "\(account.label) · \(resource.category.rawValue)",
                    accountId: account.id
                ))
            }
        }

        // --- Cost insight (always present when there's data) ---
        if totalCost > 0 {
            let topSpender = accounts
                .compactMap { acct -> (Account, Decimal)? in
                    guard let cost = statuses[acct.id]?.totalMonthlyCost, cost > 0 else { return nil }
                    return (acct, cost)
                }
                .max(by: { $0.1 < $1.1 })

            let detail = topSpender.map { "Highest: \($0.0.label) \(Formatters.formatCost($0.1))" }

            insights.append(Insight(
                priority: .info,
                icon: "dollarsign.circle.fill",
                iconColor: .grafanaGreen,
                title: "Monthly cost \(Formatters.formatCost(totalCost))",
                detail: detail,
                accountId: nil
            ))
        }

        // --- All clear ---
        if insights.isEmpty {
            if accounts.isEmpty {
                insights.append(Insight(
                    priority: .info,
                    icon: "plus.circle.fill",
                    iconColor: .grafanaBlue,
                    title: "No accounts configured",
                    detail: "Open Dashboard to add your first account",
                    accountId: nil
                ))
            } else {
                insights.append(Insight(
                    priority: .info,
                    icon: "checkmark.shield.fill",
                    iconColor: .grafanaGreen,
                    title: "All systems healthy",
                    detail: "\(accounts.count) account\(accounts.count == 1 ? "" : "s"), nothing needs attention",
                    accountId: nil
                ))
            }
        }

        // Sort: highest priority first, then by title for stability
        return insights.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return a.title < b.title
        }
    }
}
