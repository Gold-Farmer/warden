import Foundation
import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    let registry: ServiceRegistry
    let scheduler: RefreshScheduler
    let accountStore: AccountStore

    var accountStatuses: [UUID: ProviderStatus] = [:]
    var errors: [UUID: Error] = [:]
    var isLoading = false
    var lastRefresh: Date?

    // Computed
    var totalMonthlyCost: Decimal {
        accountStatuses.values.compactMap(\.totalMonthlyCost).reduce(Decimal.zero, +)
    }

    var overallHealth: ProviderStatus.Health {
        let statuses = accountStatuses.values.map(\.health)
        if statuses.contains(.critical) { return .critical }
        if statuses.contains(.warning) { return .warning }
        if statuses.isEmpty { return .unknown }
        return .healthy
    }

    var configuredAccounts: [Account] {
        accountStore.accounts.filter { accountStatuses[$0.id] != nil || errors[$0.id] != nil }
    }

    init(registry: ServiceRegistry, scheduler: RefreshScheduler, accountStore: AccountStore) {
        self.registry = registry
        self.scheduler = scheduler
        self.accountStore = accountStore
        self.scheduler.onRefresh = { [weak self] in
            await self?.refreshAll()
        }
    }

    func refreshAll() async {
        isLoading = true
        defer {
            isLoading = false
            lastRefresh = Date()
        }

        let results = await registry.fetchAll()
        for (id, result) in results {
            switch result {
            case .success(let status):
                accountStatuses[id] = status
                errors.removeValue(forKey: id)
            case .failure(let error):
                errors[id] = error
            }
        }
    }

    func refresh(accountId: UUID) async {
        guard let service = await registry.service(for: accountId) else { return }

        do {
            let status = try await service.fetchStatus()
            accountStatuses[accountId] = status
            errors.removeValue(forKey: accountId)
        } catch {
            errors[accountId] = error
        }
    }

    func loadCredentialsAndConfigure() async {
        let keychain = KeychainManager.shared

        for account in accountStore.accounts {
            let service = makeService(for: account.providerType)
            await registry.register(service, for: account.id)

            if let creds = keychain.load(for: account.id) {
                try? await service.configure(with: creds)
            }
        }
    }

    private func makeService(for provider: Provider) -> any ProviderService {
        switch provider {
        case .aws: AWSService()
        case .gcp: GCPService()
        case .azure: AzureService()
        case .cloudflare: CloudflareService()
        case .openai: OpenAIService()
        case .anthropic: AnthropicService()
        case .gemini: GeminiService()
        case .grok: GrokService()
        }
    }
}
