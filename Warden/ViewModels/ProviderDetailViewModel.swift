import Foundation

@MainActor
@Observable
final class ProviderDetailViewModel {
    let provider: Provider
    private let registry: ServiceRegistry

    var status: ProviderStatus?
    var error: Error?
    var isLoading = false

    init(provider: Provider, registry: ServiceRegistry) {
        self.provider = provider
        self.registry = registry
    }

    func refresh() async {
        guard let service = await registry.service(for: provider) else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            status = try await service.fetchStatus()
            error = nil
        } catch {
            self.error = error
        }
    }
}
