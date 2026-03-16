import Foundation

actor ServiceRegistry {
    private var services: [Provider: any ProviderService] = [:]

    func register(_ service: any ProviderService) async {
        let provider = await service.provider
        services[provider] = service
    }

    func service(for provider: Provider) -> (any ProviderService)? {
        services[provider]
    }

    var allServices: [any ProviderService] {
        Array(services.values)
    }

    var configuredProviders: [Provider] {
        get async {
            var result: [Provider] = []
            for (provider, service) in services {
                if await service.isConfigured {
                    result.append(provider)
                }
            }
            return result
        }
    }

    func fetchAll() async -> [Provider: Result<ProviderStatus, Error>] {
        await withTaskGroup(of: (Provider, Result<ProviderStatus, Error>).self) { group in
            for (provider, service) in services where await service.isConfigured {
                group.addTask {
                    do {
                        let status = try await service.fetchStatus()
                        return (provider, .success(status))
                    } catch {
                        return (provider, .failure(error))
                    }
                }
            }

            var results: [Provider: Result<ProviderStatus, Error>] = [:]
            for await (provider, result) in group {
                results[provider] = result
            }
            return results
        }
    }
}
