import Foundation

@MainActor
@Observable
final class ProviderDetailViewModel {
    let account: Account
    private let registry: ServiceRegistry

    var status: ProviderStatus?
    var error: Error?
    var isLoading = false

    init(account: Account, registry: ServiceRegistry) {
        self.account = account
        self.registry = registry
    }

    func refresh() async {
        guard let service = await registry.service(for: account.id) else { return }
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
