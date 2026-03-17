import Foundation

// MARK: - Severity

enum Severity: Int, Sendable, Comparable {
    case nominal = 0
    case info = 1
    case warning = 2
    case critical = 3

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - MetricCategory (superset of ResourceCategory)

enum MetricCategory: String, Codable, Sendable, CaseIterable {
    case compute = "Compute"
    case storage = "Storage"
    case network = "Network"
    case database = "Database"
    case serverless = "Serverless"
    case ai = "AI / ML"
    case cdn = "CDN / Edge"
    case billing = "Billing"
    case cicd = "CI / CD"
    case auth = "Auth"
    case monitoring = "Monitoring"
    case communication = "Communication"
    case security = "Security"
    case other = "Other"

    init(from resourceCategory: ResourceCategory) {
        switch resourceCategory {
        case .compute: self = .compute
        case .storage: self = .storage
        case .network: self = .network
        case .database: self = .database
        case .serverless: self = .serverless
        case .ai: self = .ai
        case .cdn: self = .cdn
        case .billing: self = .billing
        case .other: self = .other
        }
    }
}

// MARK: - MetricUnit (superset of QuotaUnit)

enum MetricUnit: String, Codable, Sendable {
    // Existing
    case count, bytes, kilobytes, megabytes, gigabytes, terabytes
    case dollars, tokens, requests, invocations, hours, percentage
    // New
    case seats, hosts, connections, events, messages, emails
    case minutes, days, operations

    var symbol: String {
        switch self {
        case .count: ""
        case .bytes: "B"
        case .kilobytes: "KB"
        case .megabytes: "MB"
        case .gigabytes: "GB"
        case .terabytes: "TB"
        case .dollars: "$"
        case .tokens: "tokens"
        case .requests: "req"
        case .invocations: "inv"
        case .hours: "hrs"
        case .percentage: "%"
        case .seats: "seats"
        case .hosts: "hosts"
        case .connections: "conn"
        case .events: "events"
        case .messages: "msgs"
        case .emails: "emails"
        case .minutes: "min"
        case .days: "days"
        case .operations: "ops"
        }
    }

    init(from quotaUnit: QuotaUnit) {
        switch quotaUnit {
        case .count: self = .count
        case .bytes: self = .bytes
        case .kilobytes: self = .kilobytes
        case .megabytes: self = .megabytes
        case .gigabytes: self = .gigabytes
        case .terabytes: self = .terabytes
        case .dollars: self = .dollars
        case .tokens: self = .tokens
        case .requests: self = .requests
        case .invocations: self = .invocations
        case .hours: self = .hours
        case .percentage: self = .percentage
        }
    }
}

// MARK: - Payloads

struct GaugePayload: Sendable, Equatable {
    let used: Double
    let limit: Double?
    let unit: MetricUnit
    let cost: Decimal?

    var fraction: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(used / limit, 1.0)
    }
}

struct MoneyPayload: Sendable, Equatable {
    let amount: Decimal
    let currency: String
    let period: Period
    let budget: Decimal?
    let direction: Direction

    enum Period: String, Sendable, Equatable {
        case daily, weekly, monthly, yearly, total
    }

    enum Direction: String, Sendable, Equatable {
        case spend, balance
    }

    var budgetFraction: Double? {
        guard let budget, budget > 0 else { return nil }
        return min(Double(truncating: (amount / budget) as NSDecimalNumber), 1.0)
    }
}

struct CountPayload: Sendable, Equatable {
    let value: Double
    let unit: MetricUnit
    let delta: Double?
    let deltaInterval: String?
}

struct RatePayload: Sendable, Equatable {
    let value: Double
    let unit: MetricUnit
    let window: String
    let limit: Double?

    var fraction: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(value / limit, 1.0)
    }
}

struct CountdownPayload: Sendable, Equatable {
    let deadline: Date
    let label: String?

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
    }
}

struct StatusPayload: Sendable, Equatable {
    let state: String
    let stateType: StateType

    enum StateType: String, Sendable, Equatable {
        case good, warning, bad, neutral
    }
}

struct PercentagePayload: Sendable, Equatable {
    let value: Double
    let warningThreshold: Double
    let criticalThreshold: Double
    let higherIsBetter: Bool

    init(value: Double, warningThreshold: Double = 0.7, criticalThreshold: Double = 0.9, higherIsBetter: Bool = true) {
        self.value = value
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.higherIsBetter = higherIsBetter
    }
}

// MARK: - MetricKind

enum MetricKind: Sendable, Equatable {
    case gauge(GaugePayload)
    case money(MoneyPayload)
    case count(CountPayload)
    case rate(RatePayload)
    case countdown(CountdownPayload)
    case status(StatusPayload)
    case percentage(PercentagePayload)

    var severity: Severity {
        switch self {
        case .gauge(let p):
            guard let fraction = p.fraction else { return .nominal }
            if fraction >= 0.9 { return .critical }
            if fraction >= 0.7 { return .warning }
            return .nominal

        case .money(let p):
            guard let fraction = p.budgetFraction else { return .nominal }
            if fraction >= 0.9 { return .critical }
            if fraction >= 0.7 { return .warning }
            return .nominal

        case .count:
            return .nominal

        case .rate(let p):
            guard let fraction = p.fraction else { return .nominal }
            if fraction >= 0.9 { return .critical }
            if fraction >= 0.7 { return .warning }
            return .nominal

        case .countdown(let p):
            let days = p.daysRemaining
            if days <= 7 { return .critical }
            if days <= 30 { return .warning }
            return .nominal

        case .status(let p):
            switch p.stateType {
            case .bad: return .critical
            case .warning: return .warning
            case .good, .neutral: return .nominal
            }

        case .percentage(let p):
            if p.higherIsBetter {
                // Lower values are worse (e.g., cache hit rate)
                if p.value <= (1 - p.criticalThreshold) { return .critical }
                if p.value <= (1 - p.warningThreshold) { return .warning }
            } else {
                // Higher values are worse (e.g., error rate)
                if p.value >= p.criticalThreshold { return .critical }
                if p.value >= p.warningThreshold { return .warning }
            }
            return .nominal
        }
    }
}

// MARK: - Metric

struct Metric: Identifiable, Sendable, Equatable {
    let id: String
    let category: MetricCategory
    let name: String
    let kind: MetricKind
    let updatedAt: Date
    let tags: [String: String]

    var severity: Severity { kind.severity }

    init(
        id: String,
        category: MetricCategory,
        name: String,
        kind: MetricKind,
        updatedAt: Date = Date(),
        tags: [String: String] = [:]
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.kind = kind
        self.updatedAt = updatedAt
        self.tags = tags
    }
}

// MARK: - Bridge from ResourceQuota

extension Metric {
    init(from quota: ResourceQuota) {
        self.id = quota.id
        self.category = MetricCategory(from: quota.category)
        self.name = quota.name
        self.kind = .gauge(GaugePayload(
            used: quota.used,
            limit: quota.limit,
            unit: MetricUnit(from: quota.unit),
            cost: quota.cost
        ))
        self.updatedAt = quota.updatedAt
        self.tags = [:]
    }
}
