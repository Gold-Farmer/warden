import CryptoKit
import Foundation
import Testing
@testable import Warden

// MARK: - CredentialEncryptor Protocol Tests

@Suite("CredentialEncryptor Protocol")
struct CredentialEncryptorProtocolTests {

    @Test("SecureEnclaveManager conforms to CredentialEncryptor")
    func secureEnclaveConformance() {
        let _: any CredentialEncryptor = SecureEnclaveManager.shared
    }

    @Test("SoftwareKeyManager conforms to CredentialEncryptor")
    func softwareKeyConformance() {
        let _: any CredentialEncryptor = SoftwareKeyManager.shared
    }

    @Test("SecureEnclave.isAvailable returns a boolean")
    func enclaveAvailabilityCheck() {
        // Just verify this doesn't crash and returns a value
        let available = SecureEnclave.isAvailable
        #expect(available == true || available == false)
    }
}

// MARK: - KeychainManager API Contract Tests
// These test the public API behavior using the real KeychainManager.
// They may be skipped in CI environments without Keychain access.

@Suite("KeychainManager Integration", .enabled(if: isKeychainAvailable()))
struct KeychainManagerIntegrationTests {

    private let keychain = KeychainManager.shared

    private func uniqueAccountId() -> UUID { UUID() }

    @Test("Save and load credentials round-trip")
    func saveLoadRoundTrip() throws {
        let id = uniqueAccountId()
        let creds = Credentials.openai(apiKey: "sk-test-\(id.uuidString.prefix(8))")

        try keychain.save(creds, for: id)
        let loaded = keychain.load(for: id)
        #expect(loaded == creds)

        try keychain.delete(for: id)
    }

    @Test("Load nonexistent account returns nil")
    func loadNonexistent() {
        #expect(keychain.load(for: uniqueAccountId()) == nil)
    }

    @Test("Delete removes credentials")
    func deleteRemoves() throws {
        let id = uniqueAccountId()
        try keychain.save(.anthropic(apiKey: "sk-ant-del-test"), for: id)
        #expect(keychain.hasCredentials(for: id) == true)

        try keychain.delete(for: id)
        #expect(keychain.load(for: id) == nil)
        #expect(keychain.hasCredentials(for: id) == false)
    }

    @Test("Overwrite existing credentials")
    func overwrite() throws {
        let id = uniqueAccountId()

        let creds1 = Credentials.openai(apiKey: "old-key-\(id.uuidString.prefix(8))")
        try keychain.save(creds1, for: id)
        let loaded1 = keychain.load(for: id)
        #expect(loaded1 == creds1)

        let creds2 = Credentials.openai(apiKey: "new-key-\(id.uuidString.prefix(8))", organizationId: "org")
        try keychain.save(creds2, for: id)
        let loaded2 = keychain.load(for: id)
        #expect(loaded2 == creds2)

        try keychain.delete(for: id)
    }

    @Test("Multiple different accounts save and load independently")
    func multipleAccounts() throws {
        let id1 = uniqueAccountId()
        let id2 = uniqueAccountId()
        let creds1 = Credentials.openai(apiKey: "key-1-\(id1.uuidString.prefix(8))")
        let creds2 = Credentials.anthropic(apiKey: "key-2-\(id2.uuidString.prefix(8))")

        try keychain.save(creds1, for: id1)
        try keychain.save(creds2, for: id2)

        #expect(keychain.load(for: id1) == creds1)
        #expect(keychain.load(for: id2) == creds2)

        try keychain.delete(for: id1)
        try keychain.delete(for: id2)
    }
}

// MARK: - Helper

/// Check if Keychain is accessible in this environment.
private func isKeychainAvailable() -> Bool {
    let testKeychain = KeychainAccess.Keychain(service: "com.warden.test-probe")
    do {
        try testKeychain.set("probe", key: "probe")
        try testKeychain.remove("probe")
        return true
    } catch {
        return false
    }
}

import KeychainAccess
