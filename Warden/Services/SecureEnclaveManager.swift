import CryptoKit
import Foundation
@preconcurrency import KeychainAccess
import os

/// Manages Secure Enclave-backed encryption for credential storage.
///
/// Architecture:
/// - A P-256 key pair lives in the Secure Enclave (device-bound, non-exportable)
/// - A random AES-256 DEK (Data Encryption Key) is wrapped via ECDH with the Enclave key
/// - Credentials are encrypted with the DEK using AES-256-GCM
/// - No biometric/password prompt — fully transparent operation
final class SecureEnclaveManager: Sendable {
    static let shared = SecureEnclaveManager()

    private let internalKeychain = Keychain(service: "com.warden.internal")
        .accessibility(.whenUnlockedThisDeviceOnly)

    private static let enclaveKeyTag = "com.warden.enclave.key-data"
    private static let wrappedDEKTag = "com.warden.wrapped-dek"
    private static let dekSalt = Data("com.warden.dek-wrap".utf8)

    private let cachedDEK: OSAllocatedUnfairLock<SymmetricKey?> = .init(initialState: nil)

    private init() {}

    // MARK: - Public API

    /// Encrypt plaintext data. Returns `nonce(12) || ciphertext || tag(16)`.
    func encrypt(_ plaintext: Data) throws -> Data {
        let dek = try getOrCreateDEK()
        let sealedBox = try AES.GCM.seal(plaintext, using: dek)
        guard let combined = sealedBox.combined else {
            throw EnclaveError.encryptionFailed
        }
        return combined
    }

    /// Decrypt a blob previously produced by `encrypt(_:)`.
    func decrypt(_ blob: Data) throws -> Data {
        let dek = try getOrCreateDEK()
        let sealedBox = try AES.GCM.SealedBox(combined: blob)
        return try AES.GCM.open(sealedBox, using: dek)
    }

    // MARK: - Secure Enclave Key

    /// Load or create the Secure Enclave P-256 key agreement key.
    private func getOrCreateEnclaveKey() throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        // Try loading existing key
        if let keyData = try? internalKeychain.getData(Self.enclaveKeyTag) {
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keyData)
        }

        // Create new key (no biometric requirement)
        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            nil
        )!

        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
            compactRepresentable: false,
            accessControl: accessControl
        )

        // Persist the opaque key data
        try internalKeychain.set(key.dataRepresentation, key: Self.enclaveKeyTag)
        return key
    }

    // MARK: - DEK Management

    /// Get the cached DEK, or unwrap/create it.
    private func getOrCreateDEK() throws -> SymmetricKey {
        // Check cache first
        if let cached = cachedDEK.withLock({ $0 }) {
            return cached
        }

        let enclaveKey = try getOrCreateEnclaveKey()

        // Try unwrapping existing DEK
        if let wrappedBlob = try? internalKeychain.getData(Self.wrappedDEKTag) {
            if let dek = try? unwrapDEK(wrappedBlob, using: enclaveKey) {
                cachedDEK.withLock { $0 = dek }
                return dek
            }
            // Key mismatch (e.g. signing identity changed) — regenerate
            try? internalKeychain.remove(Self.wrappedDEKTag)
        }

        // Generate new DEK and wrap it
        let dek = SymmetricKey(size: .bits256)
        let wrappedBlob = try wrapDEK(dek, using: enclaveKey)
        try internalKeychain.set(wrappedBlob, key: Self.wrappedDEKTag)
        cachedDEK.withLock { $0 = dek }
        return dek
    }

    /// Wrap the DEK using ECDH key agreement with the Enclave key.
    ///
    /// Stored format: `ephemeralPublicKey(65) || nonce(12) || ciphertext(32) || tag(16)` = 125 bytes
    private func wrapDEK(_ dek: SymmetricKey, using enclaveKey: SecureEnclave.P256.KeyAgreement.PrivateKey) throws -> Data {
        // Generate ephemeral key for ECDH
        let ephemeral = P256.KeyAgreement.PrivateKey()

        // Derive wrapping key via ECDH + HKDF
        let sharedSecret = try enclaveKey.sharedSecretFromKeyAgreement(with: ephemeral.publicKey)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Self.dekSalt,
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Encrypt the DEK
        let dekData = dek.withUnsafeBytes { Data($0) }
        let sealedBox = try AES.GCM.seal(dekData, using: wrappingKey)

        // Pack: ephemeral public key || sealed box
        var blob = Data()
        blob.append(ephemeral.publicKey.rawRepresentation) // 65 bytes
        blob.append(sealedBox.combined!)                    // 12 + 32 + 16 = 60 bytes
        return blob
    }

    /// Unwrap the DEK from a stored blob.
    private func unwrapDEK(_ blob: Data, using enclaveKey: SecureEnclave.P256.KeyAgreement.PrivateKey) throws -> SymmetricKey {
        // P-256 public key rawRepresentation = 64 bytes (x + y, no 0x04 prefix)
        let pubKeySize = 64
        guard blob.count > pubKeySize else {
            throw EnclaveError.invalidWrappedDEK
        }

        let pubKeyData = blob.prefix(pubKeySize)
        let sealedData = blob.dropFirst(pubKeySize)

        // Reconstruct ephemeral public key
        let ephemeralPub = try P256.KeyAgreement.PublicKey(rawRepresentation: pubKeyData)

        // Re-derive wrapping key
        let sharedSecret = try enclaveKey.sharedSecretFromKeyAgreement(with: ephemeralPub)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Self.dekSalt,
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Decrypt the DEK
        let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
        let dekData = try AES.GCM.open(sealedBox, using: wrappingKey)

        return SymmetricKey(data: dekData)
    }

    // MARK: - Errors

    enum EnclaveError: LocalizedError {
        case enclaveNotAvailable
        case encryptionFailed
        case invalidWrappedDEK

        var errorDescription: String? {
            switch self {
            case .enclaveNotAvailable:
                "Secure Enclave is not available on this device."
            case .encryptionFailed:
                "Failed to encrypt data."
            case .invalidWrappedDEK:
                "Wrapped DEK data is corrupted."
            }
        }
    }
}

// MARK: - Software Fallback

/// For devices without Secure Enclave (older Intel Macs without T2).
/// Uses a software P-256 key with the same ECDH + AES-GCM scheme.
/// Less secure (key is extractable from memory) but functionally identical.
final class SoftwareKeyManager: Sendable {
    static let shared = SoftwareKeyManager()

    private let internalKeychain = Keychain(service: "com.warden.internal.sw")
        .accessibility(.whenUnlockedThisDeviceOnly)

    private static let keyTag = "com.warden.sw.key-data"
    private static let wrappedDEKTag = "com.warden.sw.wrapped-dek"
    private static let dekSalt = Data("com.warden.dek-wrap".utf8)

    private let cachedDEK: OSAllocatedUnfairLock<SymmetricKey?> = .init(initialState: nil)

    private init() {}

    func encrypt(_ plaintext: Data) throws -> Data {
        let dek = try getOrCreateDEK()
        let sealedBox = try AES.GCM.seal(plaintext, using: dek)
        guard let combined = sealedBox.combined else {
            throw SecureEnclaveManager.EnclaveError.encryptionFailed
        }
        return combined
    }

    func decrypt(_ blob: Data) throws -> Data {
        let dek = try getOrCreateDEK()
        let sealedBox = try AES.GCM.SealedBox(combined: blob)
        return try AES.GCM.open(sealedBox, using: dek)
    }

    private func getOrCreateKey() throws -> P256.KeyAgreement.PrivateKey {
        if let keyData = try? internalKeychain.getData(Self.keyTag) {
            return try P256.KeyAgreement.PrivateKey(rawRepresentation: keyData)
        }
        let key = P256.KeyAgreement.PrivateKey()
        try internalKeychain.set(key.rawRepresentation, key: Self.keyTag)
        return key
    }

    private func getOrCreateDEK() throws -> SymmetricKey {
        if let cached = cachedDEK.withLock({ $0 }) {
            return cached
        }

        let key = try getOrCreateKey()

        if let wrappedBlob = try? internalKeychain.getData(Self.wrappedDEKTag) {
            if let dek = try? unwrapDEK(wrappedBlob, using: key) {
                cachedDEK.withLock { $0 = dek }
                return dek
            }
            // Key mismatch — regenerate
            try? internalKeychain.remove(Self.wrappedDEKTag)
        }

        let dek = SymmetricKey(size: .bits256)
        let wrappedBlob = try wrapDEK(dek, using: key)
        try internalKeychain.set(wrappedBlob, key: Self.wrappedDEKTag)
        cachedDEK.withLock { $0 = dek }
        return dek
    }

    private func wrapDEK(_ dek: SymmetricKey, using privateKey: P256.KeyAgreement.PrivateKey) throws -> Data {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeral.publicKey)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Self.dekSalt, sharedInfo: Data(), outputByteCount: 32
        )
        let dekData = dek.withUnsafeBytes { Data($0) }
        let sealedBox = try AES.GCM.seal(dekData, using: wrappingKey)
        var blob = Data()
        blob.append(ephemeral.publicKey.rawRepresentation)
        blob.append(sealedBox.combined!)
        return blob
    }

    private func unwrapDEK(_ blob: Data, using privateKey: P256.KeyAgreement.PrivateKey) throws -> SymmetricKey {
        let pubKeySize = 65
        guard blob.count > pubKeySize else {
            throw SecureEnclaveManager.EnclaveError.invalidWrappedDEK
        }
        let ephemeralPub = try P256.KeyAgreement.PublicKey(rawRepresentation: blob.prefix(pubKeySize))
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPub)
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Self.dekSalt, sharedInfo: Data(), outputByteCount: 32
        )
        let sealedBox = try AES.GCM.SealedBox(combined: blob.dropFirst(pubKeySize))
        let dekData = try AES.GCM.open(sealedBox, using: wrappingKey)
        return SymmetricKey(data: dekData)
    }
}
