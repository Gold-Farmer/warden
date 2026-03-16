import Foundation

actor GeminiService: ProviderService {
    let provider = Provider.gemini
    private(set) var isConfigured = false
    private var apiKey = ""

    func configure(with credentials: Credentials) throws {
        guard case .gemini(let key) = credentials else {
            throw ProviderServiceError.invalidCredentials
        }
        apiKey = key
        isConfigured = true
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard isConfigured else { throw ProviderServiceError.notConfigured }

        async let models = fetchAvailableModels()
        async let rateLimits = fetchRateLimits()

        var resources: [ResourceQuota] = []
        if let r = try? await models { resources.append(contentsOf: r) }
        if let r = try? await rateLimits { resources.append(contentsOf: r) }

        return ProviderStatus(
            provider: .gemini,
            resources: resources,
            totalMonthlyCost: nil,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    // MARK: - Models

    private func fetchAvailableModels() async throws -> [ResourceQuota] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!

        struct ModelsResponse: Decodable {
            let models: [Model]?
            struct Model: Decodable {
                let name: String
                let displayName: String?
                let inputTokenLimit: Int?
                let outputTokenLimit: Int?
            }
        }

        let response: ModelsResponse = try await HTTPClient.shared.request(url)
        let modelCount = response.models?.count ?? 0

        var resources = [
            ResourceQuota(
                id: "gemini-models-available",
                category: .ai,
                name: "Available Models",
                used: Double(modelCount),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]

        // Add context window info for key models
        if let models = response.models {
            for model in models where model.name.contains("gemini") {
                if let inputLimit = model.inputTokenLimit {
                    resources.append(ResourceQuota(
                        id: "gemini-context-\(model.name)",
                        category: .ai,
                        name: "\(model.displayName ?? model.name) Context",
                        used: 0,
                        limit: Double(inputLimit),
                        unit: .tokens,
                        cost: nil,
                        updatedAt: Date()
                    ))
                }
            }
        }

        return resources
    }

    // MARK: - Rate Limits

    private func fetchRateLimits() async throws -> [ResourceQuota] {
        // Gemini rate limit info comes from response headers
        // Make a lightweight request to probe
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        let (_, _, headers) = try await HTTPClient.shared.rawRequest(url)

        var resources: [ResourceQuota] = []

        // Google API rate limit headers vary; check common ones
        if let remaining = headers["x-ratelimit-remaining"] as? String,
           let limit = headers["x-ratelimit-limit"] as? String,
           let remainingVal = Double(remaining),
           let limitVal = Double(limit) {
            resources.append(ResourceQuota(
                id: "gemini-rate-limit",
                category: .ai,
                name: "API Rate Limit",
                used: limitVal - remainingVal,
                limit: limitVal,
                unit: .requests,
                cost: nil,
                updatedAt: Date()
            ))
        }

        return resources
    }
}
