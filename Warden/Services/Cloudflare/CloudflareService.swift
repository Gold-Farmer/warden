import Foundation

actor CloudflareService: ProviderService {
    let provider = Provider.cloudflare
    private(set) var isConfigured = false
    private var apiToken = ""
    private var accountId = ""

    func configure(with credentials: Credentials) throws {
        guard case .cloudflare(let token, let account) = credentials else {
            throw ProviderServiceError.invalidCredentials
        }
        apiToken = token
        accountId = account
        isConfigured = true
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard isConfigured else { throw ProviderServiceError.notConfigured }

        async let workers = fetchWorkers()
        async let r2 = fetchR2Buckets()
        async let kv = fetchKVNamespaces()
        async let pages = fetchPages()

        var resources: [ResourceQuota] = []
        if let r = try? await workers { resources.append(contentsOf: r) }
        if let r = try? await r2 { resources.append(contentsOf: r) }
        if let r = try? await kv { resources.append(contentsOf: r) }
        if let r = try? await pages { resources.append(contentsOf: r) }

        return ProviderStatus(
            provider: .cloudflare,
            resources: resources,
            totalMonthlyCost: nil,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    private var authHeaders: [String: String] {
        ["Authorization": "Bearer \(apiToken)"]
    }

    private let baseURL = "https://api.cloudflare.com/client/v4"

    // MARK: - Workers

    private func fetchWorkers() async throws -> [ResourceQuota] {
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/workers/scripts")!

        struct CFResponse<T: Decodable>: Decodable {
            let success: Bool
            let result: T?
        }
        struct Worker: Decodable {
            let id: String
        }

        let response: CFResponse<[Worker]> = try await HTTPClient.shared.request(url, headers: authHeaders)
        let count = response.result?.count ?? 0

        return [
            ResourceQuota(
                id: "cf-workers",
                category: .serverless,
                name: "Workers Scripts",
                used: Double(count),
                limit: 100, // free plan limit
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - R2

    private func fetchR2Buckets() async throws -> [ResourceQuota] {
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/r2/buckets")!

        struct CFResponse<T: Decodable>: Decodable {
            let success: Bool
            let result: T?
        }
        struct BucketsResult: Decodable {
            let buckets: [Bucket]?
            struct Bucket: Decodable { let name: String }
        }

        let response: CFResponse<BucketsResult> = try await HTTPClient.shared.request(url, headers: authHeaders)
        let count = response.result?.buckets?.count ?? 0

        return [
            ResourceQuota(
                id: "cf-r2-buckets",
                category: .storage,
                name: "R2 Buckets",
                used: Double(count),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - KV

    private func fetchKVNamespaces() async throws -> [ResourceQuota] {
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/storage/kv/namespaces")!

        struct CFResponse<T: Decodable>: Decodable {
            let success: Bool
            let result: T?
        }
        struct KVNamespace: Decodable {
            let id: String
            let title: String
        }

        let response: CFResponse<[KVNamespace]> = try await HTTPClient.shared.request(url, headers: authHeaders)
        let count = response.result?.count ?? 0

        return [
            ResourceQuota(
                id: "cf-kv-namespaces",
                category: .storage,
                name: "KV Namespaces",
                used: Double(count),
                limit: 100,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - Pages

    private func fetchPages() async throws -> [ResourceQuota] {
        let url = URL(string: "\(baseURL)/accounts/\(accountId)/pages/projects")!

        struct CFResponse<T: Decodable>: Decodable {
            let success: Bool
            let result: T?
        }
        struct PagesProject: Decodable {
            let name: String
        }

        let response: CFResponse<[PagesProject]> = try await HTTPClient.shared.request(url, headers: authHeaders)
        let count = response.result?.count ?? 0

        return [
            ResourceQuota(
                id: "cf-pages",
                category: .cdn,
                name: "Pages Projects",
                used: Double(count),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }
}
