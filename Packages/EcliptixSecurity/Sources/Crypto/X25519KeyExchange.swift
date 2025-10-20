import Foundation
import Crypto
import EcliptixCore

// MARK: - X25519 Key Exchange Service
/// Provides X25519 Diffie-Hellman key exchange (migrated from C# Sodium/libsodium X25519 usage)
public final class X25519KeyExchange: KeyExchangeService {

    public init() {}

    // MARK: - Generate Key Pair
    public func generateKeyPair() -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Curve25519.KeyAgreement.PublicKey) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        return (privateKey, publicKey)
    }

    // MARK: - Perform Key Agreement
    public func performKeyAgreement(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        publicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SharedSecret {
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }

    // MARK: - Perform Key Agreement with Raw Bytes
    /// Performs key agreement using raw byte representations
    /// This is useful when keys come from Protocol Buffers or network
    public func performKeyAgreementWithBytes(
        privateKeyBytes: Data,
        publicKeyBytes: Data
    ) throws -> Data {
        guard privateKeyBytes.count == CryptographicConstants.x25519PrivateKeySize else {
            throw SecurityError.invalidKey
        }

        guard publicKeyBytes.count == CryptographicConstants.x25519PublicKeySize else {
            throw SecurityError.invalidKey
        }

        // Create private key from raw representation
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyBytes)

        // Create public key from raw representation
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKeyBytes)

        // Perform key agreement
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)

        // Return the shared secret as Data
        return sharedSecret.withUnsafeBytes { Data($0) }
    }

    // MARK: - Generate Public Key from Private
    public func generatePublicKey(from privateKey: Curve25519.KeyAgreement.PrivateKey) -> Curve25519.KeyAgreement.PublicKey {
        return privateKey.publicKey
    }

    // MARK: - Key Serialization
    /// Converts a private key to raw bytes (32 bytes)
    public func privateKeyToBytes(_ privateKey: Curve25519.KeyAgreement.PrivateKey) -> Data {
        return privateKey.rawRepresentation
    }

    /// Converts a public key to raw bytes (32 bytes)
    public func publicKeyToBytes(_ publicKey: Curve25519.KeyAgreement.PublicKey) -> Data {
        return publicKey.rawRepresentation
    }

    /// Creates a private key from raw bytes
    public func privateKeyFromBytes(_ bytes: Data) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard bytes.count == CryptographicConstants.x25519PrivateKeySize else {
            throw SecurityError.invalidKey
        }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)
    }

    /// Creates a public key from raw bytes
    public func publicKeyFromBytes(_ bytes: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        guard bytes.count == CryptographicConstants.x25519PublicKeySize else {
            throw SecurityError.invalidKey
        }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes)
    }
}

// MARK: - HKDF Key Derivation
/// HKDF (HMAC-based Key Derivation Function) for deriving keys from shared secrets
/// Migrated from C# HKDF usage in protocol system
public struct HKDFKeyDerivation {

    /// Derives a key using HKDF-SHA256
    /// - Parameters:
    ///   - inputKeyMaterial: The input key material (e.g., shared secret)
    ///   - salt: Optional salt value
    ///   - info: Context and application specific information
    ///   - outputByteCount: Desired output length
    /// - Returns: Derived key material
    public static func deriveKey(
        inputKeyMaterial: Data,
        salt: Data? = nil,
        info: Data,
        outputByteCount: Int
    ) throws -> Data {
        let inputKey = SymmetricKey(data: inputKeyMaterial)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt ?? Data(),
            info: info,
            outputByteCount: outputByteCount
        )

        return derivedKey.withUnsafeBytes { Data($0) }
    }

    /// Derives multiple keys from a root key (used in ratcheting)
    /// Migrated from the protocol system's key derivation for chain and message keys
    public static func deriveChainAndMessageKey(
        from chainKey: Data,
        msgInfo: [UInt8] = CryptographicConstants.msgInfo,
        chainInfo: [UInt8] = CryptographicConstants.chainInfo
    ) throws -> (messageKey: Data, nextChainKey: Data) {
        guard chainKey.count == CryptographicConstants.x25519KeySize else {
            throw SecurityError.invalidKey
        }

        // Derive message key: HKDF(chainKey, info=msgInfo)
        let messageKey = try deriveKey(
            inputKeyMaterial: chainKey,
            salt: nil,
            info: Data(msgInfo),
            outputByteCount: CryptographicConstants.aesKeySize
        )

        // Derive next chain key: HKDF(chainKey, info=chainInfo)
        let nextChainKey = try deriveKey(
            inputKeyMaterial: chainKey,
            salt: nil,
            info: Data(chainInfo),
            outputByteCount: CryptographicConstants.x25519KeySize
        )

        return (messageKey, nextChainKey)
    }

    /// Derives a root key and chain key from DH output (X3DH)
    /// Migrated from protocol initialization
    public static func deriveRootAndChainKeys(
        from dhOutput: Data,
        info: String = CryptographicConstants.x3dhInfo
    ) throws -> (rootKey: Data, chainKey: Data) {
        let infoData = Data(info.utf8)

        // Derive 64 bytes total (32 for root key, 32 for chain key)
        let derived = try deriveKey(
            inputKeyMaterial: dhOutput,
            salt: nil,
            info: infoData,
            outputByteCount: 64
        )

        let rootKey = derived.prefix(32)
        let chainKey = derived.suffix(32)

        return (Data(rootKey), Data(chainKey))
    }

    /// Derives metadata encryption key
    /// Migrated from EnvelopeBuilder metadata encryption key derivation
    public static func deriveMetadataEncryptionKey(
        from rootKey: Data
    ) throws -> Data {
        let info = Data("ecliptix-metadata-v1".utf8)

        return try deriveKey(
            inputKeyMaterial: rootKey,
            salt: nil,
            info: info,
            outputByteCount: CryptographicConstants.aesKeySize
        )
    }
}
