import Foundation
import Testing
@testable import Warden

@Suite("InsightEngine")
struct InsightEngineTests {

    // MARK: - Helpers

    private func makeAccount(
        id: UUID = UUID(),
        provider: Provider = .openai,
        label: String = "Test Account"
    ) -> Account {
        Account(id: id, providerType: provider, label: label)
    }

    private func makeStatus(
        provider: Provider = .openai,
        resources: [ResourceQuota] = [],
        cost: Decimal? = nil
    ) -> ProviderStatus {
        ProviderStatus(
            provider: provider,
            resources: resources,
            totalMonthlyCost: cost,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    private func makeResource(
        id: String = "res",
        name: String = "Test Resource",
        used: Double,
        limit: Double? = nil,
        category: ResourceCategory = .ai,
        cost: Decimal? = nil
    ) -> ResourceQuota {
        ResourceQuota(
            id: id,
            category: category,
            name: name,
            used: used,
            limit: limit,
            unit: .requests,
            cost: cost,
            updatedAt: Date()
        )
    }

    // MARK: - Empty State

    @Test("No accounts shows setup prompt")
    func noAccounts() {
        let insights = InsightEngine.evaluate(
            statuses: [:], errors: [:], accounts: [], totalCost: 0
        )

        #expect(insights.count == 1)
        #expect(insights.first?.title == "No accounts configured")
        #expect(insights.first?.priority == .info)
    }

    // MARK: - All Healthy

    @Test("All healthy accounts shows all-clear message")
    func allHealthy() {
        let account = makeAccount()
        let resource = makeResource(name: "Requests", used: 50, limit: 1000)
        let status = makeStatus(resources: [resource])

        let insights = InsightEngine.evaluate(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 0
        )

        let allClear = insights.first { $0.title == "All systems healthy" }
        #expect(allClear != nil)
    }

    // MARK: - Critical Resources

    @Test("Critical resource generates critical insight")
    func criticalResource() {
        let account = makeAccount(label: "Prod OpenAI")
        let resource = makeResource(name: "API Rate Limit", used: 950, limit: 1000)
        let status = makeStatus(resources: [resource])

        let insights = InsightEngine.evaluate(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 0
        )

        let critical = insights.first { $0.priority == .critical }
        #expect(critical != nil)
        #expect(critical?.title.contains("95%") == true)
        #expect(critical?.detail?.contains("Prod OpenAI") == true)
    }

    // MARK: - Warning Resources

    @Test("Warning resource generates warning insight")
    func warningResource() {
        let account = makeAccount(label: "Dev")
        let resource = makeResource(name: "Tokens", used: 800, limit: 1000)
        let status = makeStatus(resources: [resource])

        let insights = InsightEngine.evaluate(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 0
        )

        let warning = insights.first { $0.priority == .warning }
        #expect(warning != nil)
        #expect(warning?.title.contains("80%") == true)
    }

    // MARK: - Connection Errors

    @Test("Connection error generates critical insight")
    func connectionError() {
        let account = makeAccount(label: "Broken Account")
        let error = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout"])

        let insights = InsightEngine.evaluate(
            statuses: [:],
            errors: [account.id: error],
            accounts: [account],
            totalCost: 0
        )

        let errorInsight = insights.first { $0.priority == .critical }
        #expect(errorInsight != nil)
        #expect(errorInsight?.title.contains("Broken Account") == true)
        #expect(errorInsight?.title.contains("connection failed") == true)
    }

    // MARK: - Cost Insight

    @Test("Nonzero cost generates cost insight")
    func costInsight() {
        let account = makeAccount(label: "Main")
        let status = makeStatus(cost: 42.50)

        let insights = InsightEngine.evaluate(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 42.50
        )

        let costInsight = insights.first { $0.title.contains("Monthly cost") }
        #expect(costInsight != nil)
        #expect(costInsight?.priority == .info)
    }

    @Test("Cost insight shows highest spender")
    func costInsightHighestSpender() {
        let acct1 = makeAccount(provider: .openai, label: "OpenAI Prod")
        let acct2 = makeAccount(provider: .anthropic, label: "Claude Team")

        let status1 = makeStatus(provider: .openai, cost: 100)
        let status2 = makeStatus(provider: .anthropic, cost: 250)

        let insights = InsightEngine.evaluate(
            statuses: [acct1.id: status1, acct2.id: status2],
            errors: [:],
            accounts: [acct1, acct2],
            totalCost: 350
        )

        let costInsight = insights.first { $0.title.contains("Monthly cost") }
        #expect(costInsight?.detail?.contains("Claude Team") == true)
    }

    // MARK: - Priority Ordering

    @Test("Critical insights come before warnings, which come before info")
    func priorityOrdering() {
        let acct1 = makeAccount(label: "Critical Account")
        let acct2 = makeAccount(label: "Warning Account")

        let criticalResource = makeResource(name: "Storage", used: 95, limit: 100)
        let warningResource = makeResource(name: "Compute", used: 75, limit: 100)

        let status1 = makeStatus(resources: [criticalResource], cost: 10)
        let status2 = makeStatus(resources: [warningResource])

        let insights = InsightEngine.evaluate(
            statuses: [acct1.id: status1, acct2.id: status2],
            errors: [:],
            accounts: [acct1, acct2],
            totalCost: 10
        )

        // Verify ordering: critical > warning > info
        var lastPriority: Insight.Priority = .critical
        for insight in insights {
            #expect(insight.priority <= lastPriority, "Insights should be sorted by decreasing priority")
            lastPriority = insight.priority
        }
    }

    // MARK: - Multiple Issues

    @Test("Multiple critical resources each produce an insight")
    func multipleCriticals() {
        let account = makeAccount()
        let res1 = makeResource(id: "r1", name: "CPU", used: 95, limit: 100)
        let res2 = makeResource(id: "r2", name: "Memory", used: 92, limit: 100)
        let status = makeStatus(resources: [res1, res2])

        let insights = InsightEngine.evaluate(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 0
        )

        let criticals = insights.filter { $0.priority == .critical }
        #expect(criticals.count == 2)
    }

    @Test("Error and critical resource both appear")
    func errorAndCriticalCoexist() {
        let errorAcct = makeAccount(label: "Down")
        let critAcct = makeAccount(label: "Hot")
        let error = NSError(domain: "test", code: -1)
        let resource = makeResource(name: "Disk", used: 99, limit: 100)
        let status = makeStatus(resources: [resource])

        let insights = InsightEngine.evaluate(
            statuses: [critAcct.id: status],
            errors: [errorAcct.id: error],
            accounts: [errorAcct, critAcct],
            totalCost: 0
        )

        let criticals = insights.filter { $0.priority == .critical }
        #expect(criticals.count == 2) // one error + one resource
    }
}
