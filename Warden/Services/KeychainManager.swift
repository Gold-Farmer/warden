import CryptoKit
import Foundation
@preconcurrency import KeychainAccess

final class KeychainManager: Sendable {
    static let shared = KeychainManager()

    private let keychain = Keychain(service: "com.warden.credentials")
        .accessibility(.whenUnlockedThisDeviceOnly)

    private init() {}

    /// Encrypt and store credentials for an account.
    func save(_ credentials: Credentials, for accountId: UUID) throws {
        let plaintext = try JSONEncoder().encode(credentials)
        let encrypted = try encryptor.encrypt(plaintext)
        try keychain.set(encrypted, key: accountId.uuidString)
    }

    /// Load and decrypt credentials for an account.
    /// Transparently migrates legacy plaintext entries.
    func load(for accountId: UUID) -> Credentials? {
        guard let data = try? keychain.getData(accountId.uuidString) else { return nil }

        // Try decrypting (current format)
        if let decrypted = try? encryptor.decrypt(data),
           let creds = try? JSONDecoder().decode(Credentials.self, from: decrypted) {
            return creds
        }

        // Fallback: legacy plaintext (pre-encryption migration)
        if let creds = try? JSONDecoder().decode(Credentials.self, from: data) {
            // Silently re-encrypt in place
            if let encrypted = try? encryptor.encrypt(data) {
                try? keychain.set(encrypted, key: accountId.uuidString)
            }
            return creds
        }

        return nil
    }

    func delete(for accountId: UUID) throws {
        try keychain.remove(accountId.uuidString)
    }

    func hasCredentials(for accountId: UUID) -> Bool {
        (try? keychain.getData(accountId.uuidString)) != nil
    }

    // MARK: - Encryption Backend

    /// Selects Secure Enclave if available, otherwise software fallback.
    private var encryptor: any CredentialEncryptor {
        if SecureEnclave.isAvailable {
            return SecureEnclaveManager.shared
        } else {
            return SoftwareKeyManager.shared
        }
    }
}

// MARK: - Unified Protocol

/// Abstraction over Secure Enclave and software encryption backends.
protocol CredentialEncryptor: Sendable {
    func encrypt(_ plaintext: Data) throws -> Data
    func decrypt(_ blob: Data) throws -> Data
}

extension SecureEnclaveManager: CredentialEncryptor {}
extension SoftwareKeyManager: CredentialEncryptor {}
