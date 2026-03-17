import Foundation

actor AnthropicService: ProviderService {
    let provider = Provider.anthropic
    private(set) var isConfigured = false
    private var apiKey = ""
    private var oauthCredentials: Credentials?

    // Cache rate limit info from the most recent API call
    private var cachedRateLimits: [ResourceQuota] = []

    func configure(with credentials: Credentials) throws {
        switch credentials {
        case .anthropic(let key):
            apiKey = key
            oauthCredentials = nil
        case .anthropicOAuth(let accessToken, _, _):
            apiKey = accessToken
            oauthCredentials = credentials
        default:
            throw ProviderServiceError.invalidCredentials
        }
        isConfigured = true
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard isConfigured else { throw ProviderServiceError.notConfigured }

        // Refresh token if expired
        if let oauth = oauthCredentials,
           case .anthropicOAuth(_, _, let expiresAt) = oauth,
           expiresAt < Date() {
            if let refreshed = await AnthropicOAuthClient.refresh(oauth) {
                try configure(with: refreshed)
            }
        }

        async let usage = fetchUsage()
        async let rateLimits = fetchRateLimitsFromProbe()

        var resources: [ResourceQuota] = []
        if let r = try? await usage { resources.append(contentsOf: r) }
        if let r = try? await rateLimits { resources.append(contentsOf: r) }

        let totalCost = resources.compactMap(\.cost).reduce(Decimal.zero, +)

        return ProviderStatus(
            provider: .anthropic,
            resources: resources,
            totalMonthlyCost: totalCost > 0 ? totalCost : nil,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    private var authHeaders: [String: String] {
        if oauthCredentials != nil {
            // OAuth tokens use Bearer auth
            return [
                "Authorization": "Bearer \(apiKey)",
                "anthropic-version": "2023-06-01",
            ]
        } else {
            return [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            ]
        }
    }

    // MARK: - Usage

    private func fetchUsage() async throws -> [ResourceQuota] {
        // Anthropic usage API — check for organization usage endpoint
        let url = URL(string: "https://api.anthropic.com/v1/organizations/usage")!
        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, headers: authHeaders)

        // If org usage endpoint is available, parse it
        guard (200..<300).contains(statusCode) else { return [] }

        struct UsageResponse: Decodable {
            let monthly_spend: Double?
            let monthly_limit: Double?
            let tokens_used: Int?
        }

        if let response = try? JSONDecoder().decode(UsageResponse.self, from: data) {
            var resources: [ResourceQuota] = []

            if let spend = response.monthly_spend {
                resources.append(ResourceQuota(
                    id: "anthropic-monthly-spend",
                    category: .billing,
                    name: "Month-to-Date Spend",
                    used: spend,
                    limit: response.monthly_limit,
                    unit: .dollars,
                    cost: Decimal(spend),
                    updatedAt: Date()
                ))
            }

            if let tokens = response.tokens_used {
                resources.append(ResourceQuota(
                    id: "anthropic-tokens-used",
                    category: .ai,
                    name: "Tokens Used (Monthly)",
                    used: Double(tokens),
                    limit: nil,
                    unit: .tokens,
                    cost: nil,
                    updatedAt: Date()
                ))
            }

            return resources
        }

        return []
    }

    // MARK: - Rate Limits

    private func fetchRateLimitsFromProbe() async throws -> [ResourceQuota] {
        // Make a lightweight request to capture rate limit headers
        let url = URL(string: "https://api.anthropic.com/v1/messages/count_tokens")!
        let body = """
        {"model":"claude-sonnet-4-20250514","messages":[{"role":"user","content":"hi"}]}
        """.data(using: .utf8)!

        let (_, _, headers) = try await HTTPClient.shared.rawRequest(
            url, method: "POST", headers: authHeaders, body: body
        )

        var resources: [ResourceQuota] = []

        // Anthropic rate limit headers
        if let remaining = headers["anthropic-ratelimit-requests-remaining"] as? String,
           let limit = headers["anthropic-ratelimit-requests-limit"] as? String,
           let remainingVal = Double(remaining),
           let limitVal = Double(limit) {
            resources.append(ResourceQuota(
                id: "anthropic-rate-requests",
                category: .ai,
                name: "Rate Limit (Requests/min)",
                used: limitVal - remainingVal,
                limit: limitVal,
                unit: .requests,
                cost: nil,
                updatedAt: Date()
            ))
        }

        if let remaining = headers["anthropic-ratelimit-tokens-remaining"] as? String,
           let limit = headers["anthropic-ratelimit-tokens-limit"] as? String,
           let remainingVal = Double(remaining),
           let limitVal = Double(limit) {
            resources.append(ResourceQuota(
                id: "anthropic-rate-tokens",
                category: .ai,
                name: "Rate Limit (Tokens/min)",
                used: limitVal - remainingVal,
                limit: limitVal,
                unit: .tokens,
                cost: nil,
                updatedAt: Date()
            ))
        }

        cachedRateLimits = resources
        return resources
    }
}
