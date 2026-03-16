import Foundation

enum Formatters {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        return f
    }()

    static let percentage: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.maximumFractionDigits = 1
        return f
    }()

    static let relativeDate: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func formatCost(_ cost: Decimal?) -> String {
        guard let cost else { return "—" }
        return currency.string(from: cost as NSDecimalNumber) ?? "$\(cost)"
    }

    static func formatUsage(_ value: Double, unit: QuotaUnit) -> String {
        switch unit {
        case .dollars:
            return currency.string(from: NSNumber(value: value)) ?? "$\(value)"
        case .bytes:
            return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
        case .gigabytes:
            return "\(decimal.string(from: NSNumber(value: value)) ?? "\(value)") GB"
        case .terabytes:
            return "\(decimal.string(from: NSNumber(value: value)) ?? "\(value)") TB"
        case .megabytes:
            return "\(decimal.string(from: NSNumber(value: value)) ?? "\(value)") MB"
        case .kilobytes:
            return "\(decimal.string(from: NSNumber(value: value)) ?? "\(value)") KB"
        case .percentage:
            return "\(decimal.string(from: NSNumber(value: value)) ?? "\(value)")%"
        case .tokens:
            return formatLargeNumber(value) + " tokens"
        case .requests:
            return formatLargeNumber(value) + " req"
        case .invocations:
            return formatLargeNumber(value) + " inv"
        case .hours:
            return "\(decimal.string(from: NSNumber(value: value)) ?? "\(value)") hrs"
        case .count:
            return formatLargeNumber(value)
        }
    }

    static func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return "\(decimal.string(from: NSNumber(value: value / 1_000_000_000)) ?? "")B"
        } else if value >= 1_000_000 {
            return "\(decimal.string(from: NSNumber(value: value / 1_000_000)) ?? "")M"
        } else if value >= 1_000 {
            return "\(decimal.string(from: NSNumber(value: value / 1_000)) ?? "")K"
        } else {
            return decimal.string(from: NSNumber(value: value)) ?? "\(value)"
        }
    }
}
