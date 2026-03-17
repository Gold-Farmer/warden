import Foundation

struct ProviderStatus: Sendable {
    let provider: Provider
    let resources: [ResourceQuota]
    let totalMonthlyCost: Decimal?
    let health: Health
    let fetchedAt: Date

    var resourcesByCategory: [(category: ResourceCategory, resources: [ResourceQuota])] {
        let grouped = Dictionary(grouping: resources, by: \.category)
        return ResourceCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (category: cat, resources: items)
        }
    }

    var topResources: [ResourceQuota] {
        resources
            .sorted { ($0.utilizationFraction ?? 0) > ($1.utilizationFraction ?? 0) }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Metric bridge

    var metrics: [Metric] {
        resources.map { Metric(from: $0) }
    }

    var metricsByCategory: [(category: MetricCategory, metrics: [Metric])] {
        let grouped = Dictionary(grouping: metrics, by: \.category)
        return MetricCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (category: cat, metrics: items)
        }
    }

    var topMetrics: [Metric] {
        metrics
            .sorted { $0.severity > $1.severity }
            .prefix(3)
            .map { $0 }
    }

    enum Health: Sendable {
        case healthy
        case warning
        case critical
        case unknown

        static func from(resources: [ResourceQuota]) -> Health {
            if resources.isEmpty { return .unknown }
            if resources.contains(where: { $0.utilizationLevel == .critical }) { return .critical }
            if resources.contains(where: { $0.utilizationLevel == .warning }) { return .warning }
            return .healthy
        }
    }
}
