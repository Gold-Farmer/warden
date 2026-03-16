import Foundation

actor ServiceRegistry {
    private var services: [UUID: any ProviderService] = [:]

    func register(_ service: any ProviderService, for accountId: UUID) {
        services[accountId] = service
    }

    func unregister(_ accountId: UUID) {
        services.removeValue(forKey: accountId)
    }

    func service(for accountId: UUID) -> (any ProviderService)? {
        services[accountId]
    }

    var allAccountIds: [UUID] {
        Array(services.keys)
    }

    func configuredAccountIds() async -> [UUID] {
        var result: [UUID] = []
        for (id, service) in services {
            if await service.isConfigured {
                result.append(id)
            }
        }
        return result
    }

    func fetchAll() async -> [UUID: Result<ProviderStatus, Error>] {
        await withTaskGroup(of: (UUID, Result<ProviderStatus, Error>).self) { group in
            for (id, service) in services where await service.isConfigured {
                group.addTask {
                    do {
                        let status = try await service.fetchStatus()
                        return (id, .success(status))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }

            var results: [UUID: Result<ProviderStatus, Error>] = [:]
            for await (id, result) in group {
                results[id] = result
            }
            return results
        }
    }
}
