import Crypto
import EcliptixCore
import Foundation

public struct EcliptixSecurity {
    public static let version = "1.0.0"

    public init() {}
}

public protocol SecureStorage {
    func save<T: Codable>(_ value: T, forKey key: String) throws
    func retrieve<T: Codable>(forKey key: String, as type: T.Type) throws -> T?
    func delete(forKey key: String) throws
    func exists(forKey key: String) -> Bool
}

public protocol CryptographicService {

    func encrypt(data: Data, key: SymmetricKey) throws -> Data

    func decrypt(data: Data, key: SymmetricKey) throws -> Data

    func generateSymmetricKey(size: SymmetricKeySize) -> SymmetricKey

    func generateNonce() -> Data
}

public protocol KeyExchangeService {

    func generateKeyPair() -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Curve25519.KeyAgreement.PublicKey)

    func performKeyAgreement(privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Curve25519.KeyAgreement.PublicKey) throws -> SharedSecret
}

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
public enum SecurityError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
    case invalidKey
    case invalidData
    case invalidInput(String)
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
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .keychainError(let status):
            return "Keychain operation failed with status: \(status)"
        case .storageError(let message):
            return "Storage error: \(message)"
        }
    }
}

public typealias DoubleRatchet = ProtocolConnection
