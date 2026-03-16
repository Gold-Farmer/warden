import Foundation
import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    let registry: ServiceRegistry
    let scheduler: RefreshScheduler

    var providerStatuses: [Provider: ProviderStatus] = [:]
    var errors: [Provider: Error] = [:]
    var isLoading = false
    var lastRefresh: Date?

    // Computed
    var totalMonthlyCost: Decimal {
        providerStatuses.values.compactMap(\.totalMonthlyCost).reduce(Decimal.zero, +)
    }

    var overallHealth: ProviderStatus.Health {
        let statuses = providerStatuses.values.map(\.health)
        if statuses.contains(.critical) { return .critical }
        if statuses.contains(.warning) { return .warning }
        if statuses.isEmpty { return .unknown }
        return .healthy
    }

    var configuredProviders: [Provider] {
        Provider.allCases.filter { providerStatuses[$0] != nil || errors[$0] != nil }
    }

    var unconfiguredProviders: [Provider] {
        Provider.allCases.filter { !configuredProviders.contains($0) }
    }

    init(registry: ServiceRegistry, scheduler: RefreshScheduler) {
        self.registry = registry
        self.scheduler = scheduler
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
        for (provider, result) in results {
            switch result {
            case .success(let status):
                providerStatuses[provider] = status
                errors.removeValue(forKey: provider)
            case .failure(let error):
                errors[provider] = error
            }
        }
    }

    func refresh(provider: Provider) async {
        guard let service = await registry.service(for: provider) else { return }

        do {
            let status = try await service.fetchStatus()
            providerStatuses[provider] = status
            errors.removeValue(forKey: provider)
        } catch {
            errors[provider] = error
        }
    }

    func loadCredentialsAndConfigure() async {
        let keychain = KeychainManager.shared
        let allServices: [(Provider, () -> any ProviderService)] = [
            (.aws, { AWSService() }),
            (.gcp, { GCPService() }),
            (.azure, { AzureService() }),
            (.cloudflare, { CloudflareService() }),
            (.openai, { OpenAIService() }),
            (.anthropic, { AnthropicService() }),
            (.gemini, { GeminiService() }),
            (.grok, { GrokService() }),
        ]

        for (provider, makeService) in allServices {
            let service = makeService()
            await registry.register(service)

            if let creds = keychain.load(for: provider) {
                try? await service.configure(with: creds)
            }
        }
    }
}
