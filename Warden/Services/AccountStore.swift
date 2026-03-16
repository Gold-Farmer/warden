import Foundation

@MainActor
@Observable
final class AccountStore {
    private(set) var accounts: [Account] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Warden", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("accounts.json")
        load()
    }

    // MARK: - CRUD

    @discardableResult
    func addAccount(providerType: Provider, label: String) -> Account {
        let account = Account(providerType: providerType, label: label)
        accounts.append(account)
        save()
        return account
    }

    func removeAccount(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        save()
    }

    func updateLabel(_ id: UUID, label: String) {
        guard let idx = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[idx].label = label
        save()
    }

    func account(for id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        accounts = (try? JSONDecoder().decode([Account].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
