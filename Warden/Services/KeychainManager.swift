import Foundation
@preconcurrency import KeychainAccess

final class KeychainManager: Sendable {
    static let shared = KeychainManager()

    private let keychain = Keychain(service: "com.warden.credentials")
        .accessibility(.whenUnlockedThisDeviceOnly)

    private init() {}

    // MARK: - Account-based (UUID key)

    func save(_ credentials: Credentials, for accountId: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.set(data, key: accountId.uuidString)
    }

    func load(for accountId: UUID) -> Credentials? {
        guard let data = try? keychain.getData(accountId.uuidString) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    func delete(for accountId: UUID) throws {
        try keychain.remove(accountId.uuidString)
    }

    func hasCredentials(for accountId: UUID) -> Bool {
        load(for: accountId) != nil
    }
}
