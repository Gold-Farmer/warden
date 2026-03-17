import Foundation
import Testing
@testable import Warden

// MARK: - Metric Model Tests

@Suite("Metric")
struct MetricTests {

    // MARK: - Gauge

    @Test("Gauge severity: critical at 90%+")
    func gaugeCritical() {
        let metric = Metric(
            id: "g1", category: .ai, name: "RPM",
            kind: .gauge(GaugePayload(used: 95, limit: 100, unit: .requests, cost: nil))
        )
        #expect(metric.severity == .critical)
    }

    @Test("Gauge severity: warning at 70-89%")
    func gaugeWarning() {
        let metric = Metric(
            id: "g2", category: .ai, name: "RPM",
            kind: .gauge(GaugePayload(used: 75, limit: 100, unit: .requests, cost: nil))
        )
        #expect(metric.severity == .warning)
    }

    @Test("Gauge severity: nominal below 70%")
    func gaugeNominal() {
        let metric = Metric(
            id: "g3", category: .ai, name: "RPM",
            kind: .gauge(GaugePayload(used: 50, limit: 100, unit: .requests, cost: nil))
        )
        #expect(metric.severity == .nominal)
    }

    @Test("Gauge without limit is nominal")
    func gaugeNoLimit() {
        let metric = Metric(
            id: "g4", category: .ai, name: "Tokens",
            kind: .gauge(GaugePayload(used: 999999, limit: nil, unit: .tokens, cost: nil))
        )
        #expect(metric.severity == .nominal)
    }

    // MARK: - Money

    @Test("Money severity: critical when over 90% of budget")
    func moneyCritical() {
        let metric = Metric(
            id: "m1", category: .billing, name: "API Cost",
            kind: .money(MoneyPayload(amount: 95, currency: "USD", period: .monthly, budget: 100, direction: .spend))
        )
        #expect(metric.severity == .critical)
    }

    @Test("Money severity: nominal without budget")
    func moneyNoBudget() {
        let metric = Metric(
            id: "m2", category: .billing, name: "API Cost",
            kind: .money(MoneyPayload(amount: 500, currency: "USD", period: .monthly, budget: nil, direction: .spend))
        )
        #expect(metric.severity == .nominal)
    }

    // MARK: - Count

    @Test("Count is always nominal")
    func countNominal() {
        let metric = Metric(
            id: "c1", category: .communication, name: "Messages Sent",
            kind: .count(CountPayload(value: 100000, unit: .messages, delta: 500, deltaInterval: "1h"))
        )
        #expect(metric.severity == .nominal)
    }

    // MARK: - Rate

    @Test("Rate severity: critical near limit")
    func rateCritical() {
        let metric = Metric(
            id: "r1", category: .ai, name: "Req/s",
            kind: .rate(RatePayload(value: 95, unit: .requests, window: "1s", limit: 100))
        )
        #expect(metric.severity == .critical)
    }

    @Test("Rate without limit is nominal")
    func rateNoLimit() {
        let metric = Metric(
            id: "r2", category: .database, name: "Ops/s",
            kind: .rate(RatePayload(value: 5000, unit: .operations, window: "1s", limit: nil))
        )
        #expect(metric.severity == .nominal)
    }

    // MARK: - Countdown

    @Test("Countdown severity: critical within 7 days")
    func countdownCritical() {
        let deadline = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let metric = Metric(
            id: "cd1", category: .security, name: "SSL Cert",
            kind: .countdown(CountdownPayload(deadline: deadline, label: "example.com"))
        )
        #expect(metric.severity == .critical)
    }

    @Test("Countdown severity: warning within 30 days")
    func countdownWarning() {
        let deadline = Calendar.current.date(byAdding: .day, value: 20, to: Date())!
        let metric = Metric(
            id: "cd2", category: .security, name: "SSL Cert",
            kind: .countdown(CountdownPayload(deadline: deadline, label: nil))
        )
        #expect(metric.severity == .warning)
    }

    @Test("Countdown severity: nominal beyond 30 days")
    func countdownNominal() {
        let deadline = Calendar.current.date(byAdding: .day, value: 90, to: Date())!
        let metric = Metric(
            id: "cd3", category: .security, name: "SSL Cert",
            kind: .countdown(CountdownPayload(deadline: deadline, label: nil))
        )
        #expect(metric.severity == .nominal)
    }

    // MARK: - Status

    @Test("Status bad is critical")
    func statusBad() {
        let metric = Metric(
            id: "s1", category: .auth, name: "Plan",
            kind: .status(StatusPayload(state: "Suspended", stateType: .bad))
        )
        #expect(metric.severity == .critical)
    }

    @Test("Status good is nominal")
    func statusGood() {
        let metric = Metric(
            id: "s2", category: .auth, name: "Plan",
            kind: .status(StatusPayload(state: "Active", stateType: .good))
        )
        #expect(metric.severity == .nominal)
    }

    // MARK: - Percentage

    @Test("Percentage higherIsBetter: low value is critical")
    func percentageLowCritical() {
        let metric = Metric(
            id: "p1", category: .cdn, name: "Cache Hit Rate",
            kind: .percentage(PercentagePayload(value: 0.05, higherIsBetter: true))
        )
        #expect(metric.severity == .critical)
    }

    @Test("Percentage higherIsBetter: high value is nominal")
    func percentageHighNominal() {
        let metric = Metric(
            id: "p2", category: .cdn, name: "Cache Hit Rate",
            kind: .percentage(PercentagePayload(value: 0.95, higherIsBetter: true))
        )
        #expect(metric.severity == .nominal)
    }

    @Test("Percentage lowerIsBetter: high value is critical")
    func percentageErrorRate() {
        let metric = Metric(
            id: "p3", category: .network, name: "Error Rate",
            kind: .percentage(PercentagePayload(value: 0.95, higherIsBetter: false))
        )
        #expect(metric.severity == .critical)
    }

    // MARK: - Bridge from ResourceQuota

    @Test("Metric from ResourceQuota preserves data")
    func bridgeFromQuota() {
        let quota = ResourceQuota(
            id: "q1", category: .ai, name: "Rate Limit",
            used: 800, limit: 1000, unit: .requests, cost: 5.50, updatedAt: Date()
        )
        let metric = Metric(from: quota)

        #expect(metric.id == "q1")
        #expect(metric.name == "Rate Limit")
        #expect(metric.category == .ai)
        #expect(metric.severity == .warning)

        if case .gauge(let p) = metric.kind {
            #expect(p.used == 800)
            #expect(p.limit == 1000)
            #expect(p.cost == 5.50)
            #expect(p.unit == .requests)
        } else {
            Issue.record("Expected gauge kind")
        }
    }

    @Test("Metric from ResourceQuota without limit is nominal")
    func bridgeNoLimit() {
        let quota = ResourceQuota(
            id: "q2", category: .other, name: "Tokens Used",
            used: 50000, limit: nil, unit: .tokens, cost: nil, updatedAt: Date()
        )
        let metric = Metric(from: quota)
        #expect(metric.severity == .nominal)
    }

    // MARK: - Tags

    @Test("Metric tags are accessible")
    func metricTags() {
        let metric = Metric(
            id: "t1", category: .ai, name: "GPT-4 RPM",
            kind: .gauge(GaugePayload(used: 10, limit: 100, unit: .requests, cost: nil)),
            tags: ["model": "gpt-4", "region": "us-east-1"]
        )
        #expect(metric.tags["model"] == "gpt-4")
        #expect(metric.tags["region"] == "us-east-1")
    }

    // MARK: - MetricCategory bridge

    @Test("MetricCategory covers all ResourceCategory cases")
    func categoryBridge() {
        for rc in ResourceCategory.allCases {
            let mc = MetricCategory(from: rc)
            #expect(mc.rawValue == rc.rawValue)
        }
    }

    // MARK: - MetricUnit bridge

    @Test("MetricUnit covers all QuotaUnit cases")
    func unitBridge() {
        let allQuotaUnits: [QuotaUnit] = [
            .count, .bytes, .kilobytes, .megabytes, .gigabytes, .terabytes,
            .dollars, .tokens, .requests, .invocations, .hours, .percentage
        ]
        for qu in allQuotaUnits {
            let mu = MetricUnit(from: qu)
            #expect(mu.symbol == qu.symbol)
        }
    }
}

// MARK: - InsightEngine Metric Evaluation Tests

@Suite("InsightEngine Metrics")
struct InsightEngineMetricTests {

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

    @Test("evaluateMetrics: critical gauge produces critical insight")
    func metricCriticalGauge() {
        let account = makeAccount(label: "Prod")
        let resource = ResourceQuota(
            id: "rpm", category: .ai, name: "RPM",
            used: 950, limit: 1000, unit: .requests, cost: nil, updatedAt: Date()
        )
        let status = makeStatus(resources: [resource])

        let insights = InsightEngine.evaluateMetrics(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 0
        )

        let critical = insights.first { $0.priority == .critical }
        #expect(critical != nil)
        #expect(critical?.title.contains("95%") == true)
    }

    @Test("evaluateMetrics: warning gauge produces warning insight")
    func metricWarningGauge() {
        let account = makeAccount(label: "Dev")
        let resource = ResourceQuota(
            id: "tok", category: .ai, name: "Tokens",
            used: 800, limit: 1000, unit: .tokens, cost: nil, updatedAt: Date()
        )
        let status = makeStatus(resources: [resource])

        let insights = InsightEngine.evaluateMetrics(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 0
        )

        let warning = insights.first { $0.priority == .warning }
        #expect(warning != nil)
        #expect(warning?.title.contains("80%") == true)
    }

    @Test("evaluateMetrics: healthy gauge produces all-clear")
    func metricHealthyGauge() {
        let account = makeAccount()
        let resource = ResourceQuota(
            id: "r", category: .ai, name: "Requests",
            used: 50, limit: 1000, unit: .requests, cost: nil, updatedAt: Date()
        )
        let status = makeStatus(resources: [resource])

        let insights = InsightEngine.evaluateMetrics(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 0
        )

        let allClear = insights.first { $0.title == "All systems healthy" }
        #expect(allClear != nil)
    }

    @Test("evaluateMetrics: connection errors still generate critical insights")
    func metricConnectionError() {
        let account = makeAccount(label: "Broken")
        let error = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout"])

        let insights = InsightEngine.evaluateMetrics(
            statuses: [:],
            errors: [account.id: error],
            accounts: [account],
            totalCost: 0
        )

        let critical = insights.first { $0.priority == .critical }
        #expect(critical != nil)
        #expect(critical?.title.contains("connection failed") == true)
    }

    @Test("evaluateMetrics: cost insight present with nonzero total")
    func metricCostInsight() {
        let account = makeAccount()
        let status = makeStatus(cost: 42.50)

        let insights = InsightEngine.evaluateMetrics(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 42.50
        )

        let cost = insights.first { $0.title.contains("Monthly cost") }
        #expect(cost != nil)
    }

    @Test("evaluateMetrics matches evaluate for gauge-only data")
    func metricEvaluateMatchesLegacy() {
        let account = makeAccount(label: "Match Test")
        let resource = ResourceQuota(
            id: "r1", category: .ai, name: "API Calls",
            used: 920, limit: 1000, unit: .requests, cost: nil, updatedAt: Date()
        )
        let status = makeStatus(resources: [resource], cost: 25)

        let legacy = InsightEngine.evaluate(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 25
        )
        let metric = InsightEngine.evaluateMetrics(
            statuses: [account.id: status],
            errors: [:],
            accounts: [account],
            totalCost: 25
        )

        // Same number of insights and same priorities
        #expect(legacy.count == metric.count)
        for (l, m) in zip(legacy, metric) {
            #expect(l.priority == m.priority)
        }
    }
}

// MARK: - ProviderStatus Metric Bridge Tests

@Suite("ProviderStatus Metrics Bridge")
struct ProviderStatusMetricBridgeTests {

    @Test("metrics computed property converts all resources")
    func metricsFromResources() {
        let resources = [
            ResourceQuota(id: "r1", category: .ai, name: "RPM", used: 50, limit: 100, unit: .requests, cost: nil, updatedAt: Date()),
            ResourceQuota(id: "r2", category: .storage, name: "Disk", used: 8, limit: 10, unit: .gigabytes, cost: 2.50, updatedAt: Date()),
        ]
        let status = ProviderStatus(
            provider: .openai, resources: resources,
            totalMonthlyCost: 2.50, health: .healthy, fetchedAt: Date()
        )

        #expect(status.metrics.count == 2)
        #expect(status.metrics[0].id == "r1")
        #expect(status.metrics[1].id == "r2")
    }

    @Test("metricsByCategory groups correctly")
    func metricsByCategory() {
        let resources = [
            ResourceQuota(id: "r1", category: .ai, name: "RPM", used: 50, limit: 100, unit: .requests, cost: nil, updatedAt: Date()),
            ResourceQuota(id: "r2", category: .ai, name: "TPM", used: 30, limit: 100, unit: .tokens, cost: nil, updatedAt: Date()),
            ResourceQuota(id: "r3", category: .storage, name: "Disk", used: 5, limit: 10, unit: .gigabytes, cost: nil, updatedAt: Date()),
        ]
        let status = ProviderStatus(
            provider: .openai, resources: resources,
            totalMonthlyCost: nil, health: .healthy, fetchedAt: Date()
        )

        let byCategory = status.metricsByCategory
        #expect(byCategory.count == 2)
        let aiGroup = byCategory.first { $0.category == .ai }
        #expect(aiGroup?.metrics.count == 2)
    }

    @Test("topMetrics returns highest severity first")
    func topMetrics() {
        let resources = [
            ResourceQuota(id: "r1", category: .ai, name: "Low", used: 10, limit: 100, unit: .requests, cost: nil, updatedAt: Date()),
            ResourceQuota(id: "r2", category: .ai, name: "Critical", used: 95, limit: 100, unit: .requests, cost: nil, updatedAt: Date()),
            ResourceQuota(id: "r3", category: .ai, name: "Warning", used: 75, limit: 100, unit: .requests, cost: nil, updatedAt: Date()),
        ]
        let status = ProviderStatus(
            provider: .openai, resources: resources,
            totalMonthlyCost: nil, health: .from(resources: resources), fetchedAt: Date()
        )

        let top = status.topMetrics
        #expect(top.count == 3)
        #expect(top[0].name == "Critical")
        #expect(top[1].name == "Warning")
    }
}
