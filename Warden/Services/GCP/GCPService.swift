import Foundation

actor GCPService: ProviderService {
    let provider = Provider.gcp
    private(set) var isConfigured = false
    private var projectId = ""
    private var accessToken = ""
    private var tokenExpiry = Date.distantPast
    private var serviceAccountJSON: Data = Data()

    func configure(with credentials: Credentials) throws {
        guard case .gcp(let json) = credentials else {
            throw ProviderServiceError.invalidCredentials
        }
        serviceAccountJSON = json

        // Extract project_id from service account JSON
        if let parsed = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
           let pid = parsed["project_id"] as? String {
            projectId = pid
        }
        isConfigured = true
    }

    func fetchStatus() async throws -> ProviderStatus {
        guard isConfigured else { throw ProviderServiceError.notConfigured }
        try await refreshTokenIfNeeded()

        async let compute = fetchComputeInstances()
        async let storage = fetchStorageBuckets()
        async let billing = fetchBillingInfo()

        var resources: [ResourceQuota] = []
        if let r = try? await compute { resources.append(contentsOf: r) }
        if let r = try? await storage { resources.append(contentsOf: r) }
        if let r = try? await billing { resources.append(contentsOf: r) }

        let totalCost = resources.compactMap(\.cost).reduce(Decimal.zero, +)

        return ProviderStatus(
            provider: .gcp,
            resources: resources,
            totalMonthlyCost: totalCost > 0 ? totalCost : nil,
            health: .from(resources: resources),
            fetchedAt: Date()
        )
    }

    // MARK: - Auth

    private func refreshTokenIfNeeded() async throws {
        guard tokenExpiry < Date() else { return }

        // Use service account JWT to get access token
        guard let sa = try? JSONSerialization.jsonObject(with: serviceAccountJSON) as? [String: Any],
              let clientEmail = sa["client_email"] as? String,
              let tokenURI = sa["token_uri"] as? String else {
            throw ProviderServiceError.invalidCredentials
        }

        let now = Date()
        let jwt = createJWT(
            issuer: clientEmail,
            scope: "https://www.googleapis.com/auth/cloud-platform",
            audience: tokenURI,
            issuedAt: now,
            expiry: now.addingTimeInterval(3600)
        )

        let url = URL(string: tokenURI)!
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
            .data(using: .utf8)!

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

    private func createJWT(issuer: String, scope: String, audience: String, issuedAt: Date, expiry: Date) -> String {
        // Simplified JWT — in production, sign with the service account's private key using Security framework
        let header = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": issuer,
            "scope": scope,
            "aud": audience,
            "iat": Int(issuedAt.timeIntervalSince1970),
            "exp": Int(expiry.timeIntervalSince1970)
        ]

        let headerB64 = try! JSONSerialization.data(withJSONObject: header).base64URLEncoded
        let claimsB64 = try! JSONSerialization.data(withJSONObject: claims).base64URLEncoded

        // TODO: Sign with RSA private key from service account JSON
        // For now, return unsigned JWT (will fail auth but structure is correct)
        return "\(headerB64).\(claimsB64)."
    }

    private var authHeaders: [String: String] {
        ["Authorization": "Bearer \(accessToken)"]
    }

    // MARK: - Compute

    private func fetchComputeInstances() async throws -> [ResourceQuota] {
        let url = URL(string: "https://compute.googleapis.com/compute/v1/projects/\(projectId)/aggregated/instances")!
        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, headers: authHeaders)

        guard (200..<300).contains(statusCode) else { return [] }

        struct AggregatedResponse: Decodable {
            let items: [String: ZoneInstances]?
            struct ZoneInstances: Decodable {
                let instances: [Instance]?
                struct Instance: Decodable {
                    let status: String?
                }
            }
        }

        let response = try JSONDecoder().decode(AggregatedResponse.self, from: data)
        let running = response.items?.values
            .flatMap { $0.instances ?? [] }
            .filter { $0.status == "RUNNING" }
            .count ?? 0

        return [
            ResourceQuota(
                id: "gcp-compute-running",
                category: .compute,
                name: "Compute Instances (Running)",
                used: Double(running),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - Storage

    private func fetchStorageBuckets() async throws -> [ResourceQuota] {
        let url = URL(string: "https://storage.googleapis.com/storage/v1/b?project=\(projectId)")!
        let (data, statusCode, _) = try await HTTPClient.shared.rawRequest(url, headers: authHeaders)

        guard (200..<300).contains(statusCode) else { return [] }

        struct BucketsResponse: Decodable {
            let items: [Bucket]?
            struct Bucket: Decodable {
                let name: String
            }
        }

        let response = try JSONDecoder().decode(BucketsResponse.self, from: data)

        return [
            ResourceQuota(
                id: "gcp-storage-buckets",
                category: .storage,
                name: "Cloud Storage Buckets",
                used: Double(response.items?.count ?? 0),
                limit: nil,
                unit: .count,
                cost: nil,
                updatedAt: Date()
            )
        ]
    }

    // MARK: - Billing

    private func fetchBillingInfo() async throws -> [ResourceQuota] {
        // GCP billing requires Cloud Billing API — simplified here
        return []
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
