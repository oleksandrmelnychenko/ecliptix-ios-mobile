import Foundation
import Crypto
import EcliptixCore

// MARK: - Security Module
/// Security module providing cryptographic primitives and secure storage

public struct EcliptixSecurity {
    public static let version = "1.0.0"

    public init() {}
}

// MARK: - Secure Storage Protocol
/// Protocol for secure storage operations (Keychain, encrypted UserDefaults, etc.)
public protocol SecureStorage {
    func save<T: Codable>(_ value: T, forKey key: String) throws
    func retrieve<T: Codable>(forKey key: String, as type: T.Type) throws -> T?
    func delete(forKey key: String) throws
    func exists(forKey key: String) -> Bool
}

// MARK: - Cryptographic Service Protocol
/// Protocol for cryptographic operations
public protocol CryptographicService {
    /// Encrypts data using ChaCha20-Poly1305
    func encrypt(data: Data, key: SymmetricKey) throws -> Data

    /// Decrypts data using ChaCha20-Poly1305
    func decrypt(data: Data, key: SymmetricKey) throws -> Data

    /// Generates a random symmetric key
    func generateSymmetricKey(size: SymmetricKeySize) -> SymmetricKey

    /// Generates a random nonce
    func generateNonce() -> Data
}

// MARK: - Key Exchange Protocol
/// Protocol for key exchange operations (X25519, etc.)
public protocol KeyExchangeService {
    /// Generates a new key pair for X25519 key exchange
    func generateKeyPair() -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Curve25519.KeyAgreement.PublicKey)

    /// Performs key agreement using X25519
    func performKeyAgreement(privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Curve25519.KeyAgreement.PublicKey) throws -> SharedSecret
}

// MARK: - OPAQUE Protocol Types
/// Types for OPAQUE password-authenticated key exchange protocol
public enum OPAQUEProtocol {
    public struct RegistrationRequest {
        public let alpha: Data
        public let publicKey: Data

        public init(alpha: Data, publicKey: Data) {
            self.alpha = alpha
            self.publicKey = publicKey
        }
    }

    public struct RegistrationResponse {
        public let beta: Data
        public let serverPublicKey: Data
        public let envelope: Data

        public init(beta: Data, serverPublicKey: Data, envelope: Data) {
            self.beta = beta
            self.serverPublicKey = serverPublicKey
            self.envelope = envelope
        }
    }

    public struct AuthenticationRequest {
        public let alpha: Data
        public let publicKey: Data

        public init(alpha: Data, publicKey: Data) {
            self.alpha = alpha
            self.publicKey = publicKey
        }
    }

    public struct AuthenticationResponse {
        public let beta: Data
        public let serverPublicKey: Data
        public let serverMac: Data

        public init(beta: Data, serverPublicKey: Data, serverMac: Data) {
            self.beta = beta
            self.serverPublicKey = serverPublicKey
            self.serverMac = serverMac
        }
    }
}

// MARK: - Security Errors
public enum SecurityError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
    case invalidKey
    case invalidData
    case keychainError(status: OSStatus)
    case storageError(String)

    public var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .keyGenerationFailed:
            return "Failed to generate cryptographic key"
        case .invalidKey:
            return "Invalid cryptographic key"
        case .invalidData:
            return "Invalid data format"
        case .keychainError(let status):
            return "Keychain operation failed with status: \(status)"
        case .storageError(let message):
            return "Storage error: \(message)"
        }
    }
}

// MARK: - Type Aliases
/// Alias for ProtocolConnection (Double Ratchet implementation)
/// This provides a more intuitive name when used in networking contexts
public typealias DoubleRatchet = ProtocolConnection
