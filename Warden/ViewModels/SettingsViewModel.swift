import Foundation

@MainActor
@Observable
final class SettingsViewModel {
    private let registry: ServiceRegistry
    private let keychain = KeychainManager.shared

    var refreshInterval: TimeInterval = 300
    var credentialForms: [Provider: CredentialForm] = [:]
    var testResults: [Provider: TestResult] = [:]
    var isTesting: [Provider: Bool] = [:]

    struct CredentialForm {
        // AWS
        var awsAccessKeyId = ""
        var awsSecretAccessKey = ""
        var awsRegion = "us-east-1"
        var awsSessionToken = ""

        // GCP
        var gcpServiceAccountJSON = ""

        // Azure
        var azureTenantId = ""
        var azureClientId = ""
        var azureClientSecret = ""
        var azureSubscriptionId = ""

        // Cloudflare
        var cloudflareApiToken = ""
        var cloudflareAccountId = ""

        // API Key providers
        var apiKey = ""
        var organizationId = ""
    }

    enum TestResult {
        case success
        case failure(String)
    }

    init(registry: ServiceRegistry) {
        self.registry = registry
        // Initialize forms for all providers
        for provider in Provider.allCases {
            credentialForms[provider] = CredentialForm()
        }
        loadExistingCredentials()
    }

    func loadExistingCredentials() {
        for provider in Provider.allCases {
            guard let creds = keychain.load(for: provider) else { continue }
            var form = credentialForms[provider] ?? CredentialForm()

            switch creds {
            case .aws(let key, let secret, let region, let token):
                form.awsAccessKeyId = key
                form.awsSecretAccessKey = secret
                form.awsRegion = region
                form.awsSessionToken = token ?? ""
            case .gcp(let json):
                form.gcpServiceAccountJSON = String(data: json, encoding: .utf8) ?? ""
            case .azure(let tenant, let client, let secret, let sub):
                form.azureTenantId = tenant
                form.azureClientId = client
                form.azureClientSecret = secret
                form.azureSubscriptionId = sub
            case .cloudflare(let token, let account):
                form.cloudflareApiToken = token
                form.cloudflareAccountId = account
            case .openai(let key, let org):
                form.apiKey = key
                form.organizationId = org ?? ""
            case .anthropic(let key):
                form.apiKey = key
            case .gemini(let key):
                form.apiKey = key
            case .grok(let key):
                form.apiKey = key
            }

            credentialForms[provider] = form
        }
    }

    func save(provider: Provider) {
        guard let form = credentialForms[provider] else { return }
        let credentials = buildCredentials(provider: provider, form: form)
        guard let credentials, credentials.isValid else { return }

        try? keychain.save(credentials, for: provider)

        // Reconfigure the service
        Task {
            if let service = await registry.service(for: provider) {
                try? await service.configure(with: credentials)
            }
        }
    }

    func testConnection(provider: Provider) async {
        guard let form = credentialForms[provider] else { return }
        let credentials = buildCredentials(provider: provider, form: form)
        guard let credentials, credentials.isValid else {
            testResults[provider] = .failure("Invalid credentials")
            return
        }

        isTesting[provider] = true
        defer { isTesting[provider] = false }

        if let service = await registry.service(for: provider) {
            do {
                try await service.configure(with: credentials)
                _ = try await service.fetchStatus()
                testResults[provider] = .success
            } catch {
                testResults[provider] = .failure(error.localizedDescription)
            }
        }
    }

    func deleteCredentials(provider: Provider) {
        try? keychain.delete(for: provider)
        credentialForms[provider] = CredentialForm()
        testResults.removeValue(forKey: provider)
    }

    private func buildCredentials(provider: Provider, form: CredentialForm) -> Credentials? {
        switch provider {
        case .aws:
            .aws(
                accessKeyId: form.awsAccessKeyId,
                secretAccessKey: form.awsSecretAccessKey,
                region: form.awsRegion,
                sessionToken: form.awsSessionToken.isEmpty ? nil : form.awsSessionToken
            )
        case .gcp:
            .gcp(serviceAccountJSON: Data(form.gcpServiceAccountJSON.utf8))
        case .azure:
            .azure(
                tenantId: form.azureTenantId,
                clientId: form.azureClientId,
                clientSecret: form.azureClientSecret,
                subscriptionId: form.azureSubscriptionId
            )
        case .cloudflare:
            .cloudflare(apiToken: form.cloudflareApiToken, accountId: form.cloudflareAccountId)
        case .openai:
            .openai(apiKey: form.apiKey, organizationId: form.organizationId.isEmpty ? nil : form.organizationId)
        case .anthropic:
            .anthropic(apiKey: form.apiKey)
        case .gemini:
            .gemini(apiKey: form.apiKey)
        case .grok:
            .grok(apiKey: form.apiKey)
        }
    }
}
