import Foundation

actor AzureService: ProviderService {
    let provider = Provider.azure
    private(set) var isConfigured = false
    private var tenantId = ""
    private var clientId = ""
    private var clientSecret = ""
    private var subscriptionId = ""
    private var accessToken = ""
    private var tokenExpiry = Date.distantPast

    func configure(with credentials: Credentials) throws {
        guard case .azure(let tenant, let client, let secret, let sub) = credentials else {
            throw ProviderServiceError.invalidCredentials
        }
        tenantId = tenant
        clientId = client
        clientSecret = secret
        subscriptionId = sub
        isConfigured = true
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard isConfigured else { throw ProviderServiceError.notConfigured }
        try await refreshTokenIfNeeded()

        async let vms = fetchVirtualMachines()
        async let storage = fetchStorageAccounts()
        async let cost = fetchCostManagement()

        var resources: [ResourceQuota] = []
        if let r = try? await vms { resources.append(contentsOf: r) }
        if let r = try? await storage { resources.append(contentsOf: r) }
        if let r = try? await cost { resources.append(contentsOf: r) }

        let totalCost = resources.compactMap(\.cost).reduce(Decimal.zero, +)

        return ProviderStatus(
            provider: .azure,
            resources: resources,
            totalMonthlyCost: totalCost > 0 ? totalCost : nil,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    // MARK: - Auth

    private func refreshTokenIfNeeded() async throws {
        guard tokenExpiry < Date() else { return }

        let url = URL(string: "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/token")!
        let body = [
            "grant_type=client_credentials",
            "client_id=\(clientId)",
            "client_secret=\(clientSecret)",
            "scope=https://management.azure.com/.default"
        ].joined(separator: "&").data(using: .utf8)!

        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(
            url, method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )

        guard (200..<300).contains(statusCode) else {
            throw ProviderServiceError.apiError(statusCode: statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(token.expires_in - 60))
    }

    private var authHeaders: [String: String] {
        ["Authorization": "Bearer \(accessToken)"]
    }

    private let apiVersion = "2023-09-01"

    // MARK: - VMs

    private func fetchVirtualMachines() async throws -> [ResourceQuota] {
        let url = URL(string: "https://management.azure.com/subscriptions/\(subscriptionId)/providers/Microsoft.Compute/virtualMachines?api-version=\(apiVersion)")!
        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, headers: authHeaders)

        guard (200..<300).contains(statusCode) else { return [] }

        struct VMListResponse: Decodable {
            let value: [VM]?
            struct VM: Decodable {
                let name: String
                let properties: Properties?
                struct Properties: Decodable {
                    let provisioningState: String?
                }
            }
        }

        let response = try JSONDecoder().decode(VMListResponse.self, from: data)
        let vms = response.value ?? []
        let running = vms.filter { $0.properties?.provisioningState == "Succeeded" }.count

        return [
            ResourceQuota(
                id: "azure-vms",
                category: .compute,
                name: "Virtual Machines",
                used: Double(running),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - Storage

    private func fetchStorageAccounts() async throws -> [ResourceQuota] {
        let url = URL(string: "https://management.azure.com/subscriptions/\(subscriptionId)/providers/Microsoft.Storage/storageAccounts?api-version=\(apiVersion)")!
        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, headers: authHeaders)

        guard (200..<300).contains(statusCode) else { return [] }

        struct StorageListResponse: Decodable {
            let value: [StorageAccount]?
            struct StorageAccount: Decodable { let name: String }
        }

        let response = try JSONDecoder().decode(StorageListResponse.self, from: data)

        return [
            ResourceQuota(
                id: "azure-storage-accounts",
                category: .storage,
                name: "Storage Accounts",
                used: Double(response.value?.count ?? 0),
                limit: 250, // default Azure limit per subscription
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - Cost

    private func fetchCostManagement() async throws -> [ResourceQuota] {
        // Azure Cost Management API requires additional setup
        return []
    }
}
