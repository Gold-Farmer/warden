import Foundation

actor GrokService: ProviderService {
    let provider = Provider.grok
    private(set) var isConfigured = false
    private var apiKey = ""

    func configure(with credentials: Credentials) throws {
        guard case .grok(let key) = credentials else {
            throw ProviderServiceError.invalidCredentials
        }
        apiKey = key
        isConfigured = true
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard isConfigured else { throw ProviderServiceError.notConfigured }

        async let keyInfo = fetchAPIKeyInfo()
        async let models = fetchModels()

        var resources: [ResourceQuota] = []
        if let r = try? await keyInfo { resources.append(contentsOf: r) }
        if let r = try? await models { resources.append(contentsOf: r) }

        let totalCost = resources.compactMap(\.cost).reduce(Decimal.zero, +)

        return ProviderStatus(
            provider: .grok,
            resources: resources,
            totalMonthlyCost: totalCost > 0 ? totalCost : nil,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    private var authHeaders: [String: String] {
        ["Authorization": "Bearer \(apiKey)"]
    }

    // MARK: - API Key Info

    private func fetchAPIKeyInfo() async throws -> [ResourceQuota] {
        // xAI API — check key info endpoint for usage/limits
        let url = URL(string: "https://api.x.ai/v1/api-key")!
        let (data, statusCode, headers) = try await HTTPClient.shared.rawRequest(url, headers: authHeaders)

        var resources: [ResourceQuota] = []

        if (200..<300).contains(statusCode) {
            struct KeyInfoResponse: Decodable {
                let name: String?
                let monthly_usage: Double?
                let monthly_limit: Double?
                let requests_remaining: Int?
                let requests_limit: Int?
            }

            if let info = try? JSONDecoder().decode(KeyInfoResponse.self, from: data) {
                if let usage = info.monthly_usage {
                    resources.append(ResourceQuota(
                        id: "grok-monthly-usage",
                        category: .billing,
                        name: "Monthly API Usage",
                        used: usage,
                        limit: info.monthly_limit,
                        unit: .dollars,
                        cost: Decimal(usage),
                        updatedAt: Date()
                    ))
                }

                if let remaining = info.requests_remaining, let limit = info.requests_limit {
                    resources.append(ResourceQuota(
                        id: "grok-rate-limit",
                        category: .ai,
                        name: "Rate Limit (Requests)",
                        used: Double(limit - remaining),
                        limit: Double(limit),
                        unit: .requests,
                        cost: nil,
                        updatedAt: Date()
                    ))
                }
            }
        }

        // Also check rate limit headers
        if let remaining = headers["x-ratelimit-remaining-requests"] as? String,
           let limit = headers["x-ratelimit-limit-requests"] as? String,
           let remainingVal = Double(remaining),
           let limitVal = Double(limit) {
            resources.append(ResourceQuota(
                id: "grok-header-rate-limit",
                category: .ai,
                name: "Rate Limit (from headers)",
                used: limitVal - remainingVal,
                limit: limitVal,
                unit: .requests,
                cost: nil,
                updatedAt: Date()
            ))
        }

        return resources
    }

    // MARK: - Models

    private func fetchModels() async throws -> [ResourceQuota] {
        let url = URL(string: "https://api.x.ai/v1/models")!

        struct ModelsResponse: Decodable {
            let data: [Model]?
            struct Model: Decodable {
                let id: String
            }
        }

        let response: ModelsResponse = try await HTTPClient.shared.request(url, headers: authHeaders)
        let count = response.data?.count ?? 0

        return [
            ResourceQuota(
                id: "grok-models-available",
                category: .ai,
                name: "Available Models",
                used: Double(count),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }
}
