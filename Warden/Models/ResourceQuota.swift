import Foundation

struct ResourceQuota: Identifiable, Sendable, Equatable {
    let id: String
    let category: ResourceCategory
    let name: String
    let used: Double
    let limit: Double?
    let unit: QuotaUnit
    let cost: Decimal?
    let updatedAt: Date

    var utilizationFraction: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(used / limit, 1.0)
    }

    var utilizationLevel: UtilizationLevel {
        guard let fraction = utilizationFraction else { return .unknown }
        if fraction >= 0.9 { return .critical }
        if fraction >= 0.7 { return .warning }
        return .healthy
    }
}

enum QuotaUnit: String, Codable, Sendable {
    case count
    case bytes
    case kilobytes
    case megabytes
    case gigabytes
    case terabytes
    case dollars
    case tokens
    case requests
    case invocations
    case hours
    case percentage

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
        }
    }
}

enum ResourceCategory: String, Codable, Sendable, CaseIterable {
    case compute = "Compute"
    case storage = "Storage"
    case network = "Network"
    case database = "Database"
    case serverless = "Serverless"
    case ai = "AI / ML"
    case cdn = "CDN / Edge"
    case billing = "Billing"
    case other = "Other"
}

enum UtilizationLevel: Sendable {
    case healthy
    case warning
    case critical
    case unknown
}
