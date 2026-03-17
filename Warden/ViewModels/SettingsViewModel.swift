import Foundation

@MainActor
@Observable
final class SettingsViewModel {
    let registry: ServiceRegistry
    let accountStore: AccountStore
    private let keychain = KeychainManager.shared

    var refreshInterval: TimeInterval = 300
    var credentialForms: [UUID: CredentialForm] = [:]
    var testResults: [UUID: TestResult] = [:]
    var isTesting: [UUID: Bool] = [:]

    // Add-account sheet state
    var showingAddAccount = false
    var newAccountProvider: Provider = .aws
    var newAccountLabel = ""

    enum AWSAuthMode: String, CaseIterable {
        case accessKey = "Access Key"
        case profile = "AWS Profile"
    }

    struct CredentialForm {
        // AWS
        var awsAuthMode: AWSAuthMode = .accessKey
        var awsAccessKeyId = ""
        var awsSecretAccessKey = ""
        var awsRegion = "us-east-1"
        var awsSessionToken = ""
        var awsProfileName = "default"
        var awsProfileRegionOverride = ""

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

    init(registry: ServiceRegistry, accountStore: AccountStore) {
        self.registry = registry
        self.accountStore = accountStore
        loadExistingCredentials()
    }

    func loadExistingCredentials() {
        for account in accountStore.accounts {
            guard let creds = keychain.load(for: account.id) else {
                credentialForms[account.id] = CredentialForm()
                continue
            }
            var form = CredentialForm()
            populateForm(&form, from: creds)
            credentialForms[account.id] = form
        }
    }

    func addAccount() {
        let label = newAccountLabel.isEmpty ? newAccountProvider.displayName : newAccountLabel
        let account = accountStore.addAccount(providerType: newAccountProvider, label: label)
        credentialForms[account.id] = CredentialForm()
        newAccountLabel = ""
        newAccountProvider = .aws
        showingAddAccount = false
    }

    func removeAccount(_ account: Account) {
        try? keychain.delete(for: account.id)
        Task { await registry.unregister(account.id) }
        credentialForms.removeValue(forKey: account.id)
        testResults.removeValue(forKey: account.id)
        accountStore.removeAccount(account.id)
    }

    func save(account: Account) {
        guard let form = credentialForms[account.id] else { return }
        let credentials = buildCredentials(provider: account.providerType, form: form)
        guard let credentials, credentials.isValid else { return }

        try? keychain.save(credentials, for: account.id)

        Task {
            if let service = await registry.service(for: account.id) {
                try? await service.configure(with: credentials)
            }
        }
    }

    func testConnection(account: Account) async {
        guard let form = credentialForms[account.id] else { return }
        let credentials = buildCredentials(provider: account.providerType, form: form)
        guard let credentials, credentials.isValid else {
            testResults[account.id] = .failure("Invalid credentials")
            return
        }

        isTesting[account.id] = true
        defer { isTesting[account.id] = false }

        if let service = await registry.service(for: account.id) {
            do {
                try await service.configure(with: credentials)
                _ = try await service.fetchStatus()
                testResults[account.id] = .success
            } catch {
                testResults[account.id] = .failure(error.localizedDescription)
            }
        }
    }

    func deleteCredentials(account: Account) {
        try? keychain.delete(for: account.id)
        credentialForms[account.id] = CredentialForm()
        testResults.removeValue(forKey: account.id)
    }

    private func populateForm(_ form: inout CredentialForm, from creds: Credentials) {
        switch creds {
        case .aws(let key, let secret, let region, let token):
            form.awsAuthMode = .accessKey
            form.awsAccessKeyId = key
            form.awsSecretAccessKey = secret
            form.awsRegion = region
            form.awsSessionToken = token ?? ""
        case .awsProfile(let name, let region):
            form.awsAuthMode = .profile
            form.awsProfileName = name
            form.awsProfileRegionOverride = region ?? ""
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
        case .openaiOAuth:
            break // OAuth tokens are managed internally
        case .anthropic(let key):
            form.apiKey = key
        case .anthropicOAuth:
            break // OAuth tokens are managed internally
        case .gemini(let key):
            form.apiKey = key
        case .grok(let key):
            form.apiKey = key
        }
    }

    private func buildCredentials(provider: Provider, form: CredentialForm) -> Credentials? {
        switch provider {
        case .aws:
            switch form.awsAuthMode {
            case .accessKey:
                .aws(
                    accessKeyId: form.awsAccessKeyId,
                    secretAccessKey: form.awsSecretAccessKey,
                    region: form.awsRegion,
                    sessionToken: form.awsSessionToken.isEmpty ? nil : form.awsSessionToken
                )
            case .profile:
                .awsProfile(
                    profileName: form.awsProfileName,
                    region: form.awsProfileRegionOverride.isEmpty ? nil : form.awsProfileRegionOverride
                )
            }
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
