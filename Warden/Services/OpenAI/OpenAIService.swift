import Foundation

actor OpenAIService: ProviderService {
    let provider = Provider.openai
    private(set) var isConfigured = false
    private var apiKey = ""
    private var organizationId: String?

    func configure(with credentials: Credentials) throws {
        guard case .openai(let key, let orgId) = credentials else {
            throw ProviderServiceError.invalidCredentials
        }
        apiKey = key
        organizationId = orgId
        isConfigured = true
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard isConfigured else { throw ProviderServiceError.notConfigured }

        async let usage = fetchUsage()
        async let rateLimits = fetchRateLimits()

        var resources: [ResourceQuota] = []
        if let r = try? await usage { resources.append(contentsOf: r) }
        if let r = try? await rateLimits { resources.append(contentsOf: r) }

        let totalCost = resources.compactMap(\.cost).reduce(Decimal.zero, +)

        return ProviderStatus(
            provider: .openai,
            resources: resources,
            totalMonthlyCost: totalCost > 0 ? totalCost : nil,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    private var authHeaders: [String: String] {
        var headers = ["Authorization": "Bearer \(apiKey)"]
        if let orgId = organizationId {
            headers["OpenAI-Organization"] = orgId
        }
        return headers
    }

    // MARK: - Usage

    private func fetchUsage() async throws -> [ResourceQuota] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(Int(startOfMonth.timeIntervalSince1970))&end_time=\(Int(now.timeIntervalSince1970))&group_by=line_item")!

        struct CostsResponse: Decodable {
            let data: [CostBucket]?
            struct CostBucket: Decodable {
                let results: [CostResult]?
                struct CostResult: Decodable {
                    let line_item: String?
                    let amount: AmountInfo?
                    struct AmountInfo: Decodable {
                        let value: Double?
                        let currency: String?
                    }
                }
            }
        }

        let response: CostsResponse = try await HTTPClient.shared.request(url, headers: authHeaders)

        var resources: [ResourceQuota] = []
        var totalCost: Double = 0

        if let buckets = response.data {
            for bucket in buckets {
                for result in bucket.results ?? [] {
                    if let amount = result.amount?.value {
                        totalCost += amount
                    }
                }
            }
        }

        if totalCost > 0 {
            resources.append(ResourceQuota(
                id: "openai-monthly-cost",
                category: .billing,
                name: "Month-to-Date Cost",
                used: totalCost,
                limit: nil,
                unit: .dollars,
                cost: Decimal(totalCost),
                updatedAt: Date()
            ))
        }

        return resources
    }

    // MARK: - Rate Limits (probed from a lightweight request)

    private func fetchRateLimits() async throws -> [ResourceQuota] {
        // Make a lightweight models list request to capture rate limit headers
        let url = URL(string: "https://api.openai.com/v1/models")!
        let (_, _, headers) = try await HTTPClient.shared.rawRequest(url, headers: authHeaders)

        var resources: [ResourceQuota] = []

        if let remaining = headers["x-ratelimit-remaining-requests"] as? String,
           let limit = headers["x-ratelimit-limit-requests"] as? String,
           let remainingVal = Double(remaining),
           let limitVal = Double(limit) {
            resources.append(ResourceQuota(
                id: "openai-rate-limit-requests",
                category: .ai,
                name: "API Rate Limit (Requests)",
                used: limitVal - remainingVal,
                limit: limitVal,
                unit: .requests,
                cost: nil,
                updatedAt: Date()
            ))
        }

        if let remaining = headers["x-ratelimit-remaining-tokens"] as? String,
           let limit = headers["x-ratelimit-limit-tokens"] as? String,
           let remainingVal = Double(remaining),
           let limitVal = Double(limit) {
            resources.append(ResourceQuota(
                id: "openai-rate-limit-tokens",
                category: .ai,
                name: "API Rate Limit (Tokens)",
                used: limitVal - remainingVal,
                limit: limitVal,
                unit: .tokens,
                cost: nil,
                updatedAt: Date()
            ))
        }

        return resources
    }
}
