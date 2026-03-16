import Foundation
@preconcurrency import KeychainAccess

final class KeychainManager: Sendable {
    static let shared = KeychainManager()

    private let keychain = Keychain(service: "com.warden.credentials")
        .accessibility(.whenUnlockedThisDeviceOnly)

    private init() {}

    func save(_ credentials: Credentials, for provider: Provider) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.set(data, key: provider.rawValue)
    }

    func load(for provider: Provider) -> Credentials? {
        guard let data = try? keychain.getData(provider.rawValue) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    func delete(for provider: Provider) throws {
        try keychain.remove(provider.rawValue)
    }

    func hasCredentials(for provider: Provider) -> Bool {
        load(for: provider) != nil
    }
}
