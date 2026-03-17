import CryptoKit
import Foundation
import Testing
@testable import Warden

// MARK: - AES-GCM Encryption Logic Tests (no Keychain, no Secure Enclave)
// Tests the core encrypt/decrypt logic using an in-memory symmetric key.

@Suite("AES-GCM Encryption Logic")
struct AESGCMEncryptionTests {

    /// Simulates the encrypt/decrypt logic used by SecureEnclaveManager
    /// without touching Keychain or Secure Enclave hardware.
    private let testKey = SymmetricKey(size: .bits256)

    private func encrypt(_ plaintext: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(plaintext, using: testKey)
        return sealedBox.combined!
    }

    private func decrypt(_ blob: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: blob)
        return try AES.GCM.open(sealedBox, using: testKey)
    }

    @Test("Encrypt then decrypt returns original data")
    func encryptDecryptRoundTrip() throws {
        let plaintext = Data("Hello, Warden! 🔐".utf8)
        let encrypted = try encrypt(plaintext)
        let decrypted = try decrypt(encrypted)
        #expect(decrypted == plaintext)
    }

    @Test("Encrypted data differs from plaintext")
    func encryptedDiffersFromPlaintext() throws {
        let plaintext = Data("secret-api-key-sk-1234567890".utf8)
        let encrypted = try encrypt(plaintext)
        #expect(encrypted != plaintext)
        #expect(encrypted.count > plaintext.count)
    }

    @Test("Different plaintexts produce different ciphertexts")
    func differentPlaintextsDifferentCiphertexts() throws {
        let encrypted1 = try encrypt(Data("key-one".utf8))
        let encrypted2 = try encrypt(Data("key-two".utf8))
        #expect(encrypted1 != encrypted2)
    }

    @Test("Same plaintext produces different ciphertexts (random nonce)")
    func samePlaintextDifferentCiphertexts() throws {
        let plaintext = Data("same-data".utf8)
        let encrypted1 = try encrypt(plaintext)
        let encrypted2 = try encrypt(plaintext)
        #expect(encrypted1 != encrypted2)
    }

    @Test("Decrypt with tampered data fails")
    func decryptTamperedDataFails() throws {
        let plaintext = Data("sensitive".utf8)
        var encrypted = try encrypt(plaintext)
        encrypted[encrypted.count / 2] ^= 0xFF
        #expect(throws: (any Error).self) {
            try self.decrypt(encrypted)
        }
    }

    @Test("Decrypt with truncated data fails")
    func decryptTruncatedDataFails() throws {
        let plaintext = Data("sensitive".utf8)
        let encrypted = try encrypt(plaintext)
        let truncated = Data(encrypted.prefix(10))
        #expect(throws: (any Error).self) {
            try self.decrypt(truncated)
        }
    }

    @Test("Empty data encrypts and decrypts")
    func emptyData() throws {
        let plaintext = Data()
        let encrypted = try encrypt(plaintext)
        let decrypted = try decrypt(encrypted)
        #expect(decrypted == plaintext)
    }

    @Test("Large data (1MB) encrypts and decrypts")
    func largeData() throws {
        var plaintext = Data(count: 1_000_000)
        _ = plaintext.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        let encrypted = try encrypt(plaintext)
        let decrypted = try decrypt(encrypted)
        #expect(decrypted == plaintext)
    }

    @Test("Wrong key cannot decrypt")
    func wrongKeyCannotDecrypt() throws {
        let plaintext = Data("secret".utf8)
        let encrypted = try encrypt(plaintext)

        let wrongKey = SymmetricKey(size: .bits256)
        #expect(throws: (any Error).self) {
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            _ = try AES.GCM.open(sealedBox, using: wrongKey)
        }
    }
}

// MARK: - ECDH + DEK Wrapping Logic Tests

@Suite("ECDH DEK Wrapping")
struct ECDHDEKWrappingTests {

    private let salt = Data("test-salt".utf8)

    private func wrapDEK(_ dek: SymmetricKey, using privateKey: P256.KeyAgreement.PrivateKey) throws -> Data {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeral.publicKey)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt, sharedInfo: Data(), outputByteCount: 32
        )
        let dekData = dek.withUnsafeBytes { Data($0) }
        let sealedBox = try AES.GCM.seal(dekData, using: wrappingKey)
        var blob = Data()
        blob.append(ephemeral.publicKey.rawRepresentation)
        blob.append(sealedBox.combined!)
        return blob
    }

    private func unwrapDEK(_ blob: Data, using privateKey: P256.KeyAgreement.PrivateKey) throws -> SymmetricKey {
        let pubKeySize = 64
        let ephemeralPub = try P256.KeyAgreement.PublicKey(rawRepresentation: blob.prefix(pubKeySize))
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPub)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt, sharedInfo: Data(), outputByteCount: 32
        )
        let sealedBox = try AES.GCM.SealedBox(combined: blob.dropFirst(pubKeySize))
        let dekData = try AES.GCM.open(sealedBox, using: wrappingKey)
        return SymmetricKey(data: dekData)
    }

    @Test("Wrap and unwrap DEK round-trip")
    func wrapUnwrapRoundTrip() throws {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let dek = SymmetricKey(size: .bits256)

        let wrapped = try wrapDEK(dek, using: privateKey)
        let unwrapped = try unwrapDEK(wrapped, using: privateKey)

        // Compare key bytes
        let dekBytes = dek.withUnsafeBytes { Data($0) }
        let unwrappedBytes = unwrapped.withUnsafeBytes { Data($0) }
        #expect(dekBytes == unwrappedBytes)
    }

    @Test("Different private key cannot unwrap")
    func differentKeyCannotUnwrap() throws {
        let key1 = P256.KeyAgreement.PrivateKey()
        let key2 = P256.KeyAgreement.PrivateKey()
        let dek = SymmetricKey(size: .bits256)

        let wrapped = try wrapDEK(dek, using: key1)

        #expect(throws: (any Error).self) {
            _ = try self.unwrapDEK(wrapped, using: key2)
        }
    }

    @Test("Tampered wrapped DEK fails to unwrap")
    func tamperedWrappedDEKFails() throws {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let dek = SymmetricKey(size: .bits256)

        var wrapped = try wrapDEK(dek, using: privateKey)
        // Tamper with the ciphertext portion (after the 64-byte public key)
        wrapped[70] ^= 0xFF

        #expect(throws: (any Error).self) {
            _ = try self.unwrapDEK(wrapped, using: privateKey)
        }
    }

    @Test("Wrapped blob has expected size")
    func wrappedBlobSize() throws {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let dek = SymmetricKey(size: .bits256)

        let wrapped = try wrapDEK(dek, using: privateKey)
        // 64 (pubkey) + 12 (nonce) + 32 (encrypted DEK) + 16 (tag) = 124
        #expect(wrapped.count == 124)
    }
}

// MARK: - Credential Encryption Integration Tests (in-memory, no Keychain)

@Suite("Credential Encryption Integration")
struct CredentialEncryptionIntegrationTests {

    private let key = SymmetricKey(size: .bits256)

    @Test("Full credential encrypt/decrypt round-trip")
    func credentialRoundTrip() throws {
        let creds = Credentials.openai(apiKey: "sk-test-key-12345", organizationId: "org-abc")
        let plaintext = try JSONEncoder().encode(creds)

        let encrypted = try AES.GCM.seal(plaintext, using: key).combined!
        let decrypted = try AES.GCM.open(.init(combined: encrypted), using: key)
        let decoded = try JSONDecoder().decode(Credentials.self, from: decrypted)

        #expect(decoded == creds)
    }

    @Test("All credential types survive encryption round-trip")
    func allTypesRoundTrip() throws {
        let cases: [Credentials] = [
            .aws(accessKeyId: "AKIA", secretAccessKey: "secret", region: "us-east-1"),
            .gcp(serviceAccountJSON: Data("{\"type\":\"sa\"}".utf8)),
            .azure(tenantId: "t", clientId: "c", clientSecret: "s", subscriptionId: "sub"),
            .cloudflare(apiToken: "cf", accountId: "acct"),
            .openai(apiKey: "sk-openai"),
            .openaiOAuth(accessToken: "oat", refreshToken: "ort", expiresAt: Date(timeIntervalSince1970: 1700000000), accountId: "id"),
            .anthropic(apiKey: "sk-ant"),
            .anthropicOAuth(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 1700000000)),
            .gemini(apiKey: "gem"),
            .grok(apiKey: "grok"),
        ]

        for original in cases {
            let plaintext = try JSONEncoder().encode(original)
            let encrypted = try AES.GCM.seal(plaintext, using: key).combined!

            // Verify it's not plaintext
            let isPlaintext = (try? JSONDecoder().decode(Credentials.self, from: encrypted)) != nil
            #expect(!isPlaintext, "Encrypted data should not be valid JSON for \(original.provider)")

            let decrypted = try AES.GCM.open(.init(combined: encrypted), using: key)
            let decoded = try JSONDecoder().decode(Credentials.self, from: decrypted)
            #expect(decoded == original, "Round-trip failed for \(original.provider)")
        }
    }

    @Test("Legacy plaintext migration logic")
    func legacyMigration() throws {
        // Simulate: old data is plain JSON, new code should detect and re-encrypt
        let creds = Credentials.anthropic(apiKey: "sk-ant-legacy")
        let plainJSON = try JSONEncoder().encode(creds)

        // Attempt decrypt (should fail — it's not encrypted)
        let decryptResult = try? AES.GCM.open(.init(combined: plainJSON), using: key)
        #expect(decryptResult == nil, "Plain JSON should not decrypt as AES-GCM")

        // Fallback: decode as plain JSON (migration path)
        let decoded = try JSONDecoder().decode(Credentials.self, from: plainJSON)
        #expect(decoded == creds)

        // Re-encrypt
        let reEncrypted = try AES.GCM.seal(plainJSON, using: key).combined!
        let reDecrypted = try AES.GCM.open(.init(combined: reEncrypted), using: key)
        let final = try JSONDecoder().decode(Credentials.self, from: reDecrypted)
        #expect(final == creds)
    }
}
