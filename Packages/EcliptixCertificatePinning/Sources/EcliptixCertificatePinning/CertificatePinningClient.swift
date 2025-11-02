import CEcliptixClient
import EcliptixCore
import Foundation

public final class CertificatePinningClient {

    private var isInitialized: Bool = false
    private let initializationLock = NSLock()

    public init() {
        Log.info("[CertificatePinning] Client created (not initialized)")
    }

    deinit {
        cleanup()
    }

    public func initialize() -> Result<Void, CertificatePinningError> {
        initializationLock.lock()
        defer { initializationLock.unlock() }

        guard !isInitialized else {
            return .success(())
        }

        let result = ecliptix_client_init()

        guard result == 0 else {
            let errorMessage = getErrorMessage()
            Log.error("[CertificatePinning] Initialization failed: \(errorMessage)")
            return .failure(.initializationFailed(errorMessage))
        }

        isInitialized = true
        Log.info("[CertificatePinning] [OK] Initialized successfully")
        return .success(())
    }

    public func cleanup() {
        initializationLock.lock()
        defer { initializationLock.unlock() }

        guard isInitialized else { return }

        ecliptix_client_cleanup()
        isInitialized = false
        Log.info("[CertificatePinning] Cleaned up")
    }

    public func verifySignature(data: Data, signature: Data) -> Result<Bool, CertificatePinningError> {
        guard isInitialized else {
            return .failure(.notInitialized)
        }

        guard !data.isEmpty else {
            return .failure(.invalidInput("Data cannot be empty"))
        }

        guard !signature.isEmpty else {
            return .failure(.invalidInput("Signature cannot be empty"))
        }

        let result: ecliptix_result_t = data.withUnsafeBytes { dataBytes in
            signature.withUnsafeBytes { sigBytes in
                ecliptix_client_verify(
                    dataBytes.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    sigBytes.bindMemory(to: UInt8.self).baseAddress,
                    signature.count
                )
            }
        }

        switch result.rawValue {
        case 0:
            Log.debug("[CertificatePinning] Signature verification succeeded")
            return .success(true)
        case -3:
            Log.warning("[CertificatePinning] Signature verification failed")
            return .success(false)
        default:
            let errorMessage = getErrorMessage()
            Log.error("[CertificatePinning] Signature verification error: \(errorMessage)")
            return .failure(.verificationError(errorMessage))
        }
    }

    public func encrypt(plaintext: Data) -> Result<Data, CertificatePinningError> {
        guard isInitialized else {
            return .failure(.notInitialized)
        }

        guard !plaintext.isEmpty else {
            return .failure(.invalidInput("Plaintext cannot be empty"))
        }

        var ciphertext = Data(count: 256)
        var ciphertextLength = ciphertext.count

        let result: ecliptix_result_t = plaintext.withUnsafeBytes { plaintextBytes in
            ciphertext.withUnsafeMutableBytes { ciphertextBytes in
                ecliptix_client_encrypt(
                    plaintextBytes.bindMemory(to: UInt8.self).baseAddress,
                    plaintext.count,
                    ciphertextBytes.bindMemory(to: UInt8.self).baseAddress,
                    &ciphertextLength
                )
            }
        }

        guard result.rawValue == 0 else {
            let errorMessage = getErrorMessage()
            Log.error("[CertificatePinning] RSA encryption failed: \(errorMessage)")
            return .failure(.encryptionFailed(errorMessage))
        }

        ciphertext = ciphertext.prefix(ciphertextLength)

        Log.debug("[CertificatePinning] Encrypted \(plaintext.count) bytes → \(ciphertext.count) bytes")
        return .success(ciphertext)
    }

    public func decrypt(ciphertext: Data) -> Result<Data, CertificatePinningError> {
        guard isInitialized else {
            return .failure(.notInitialized)
        }

        guard !ciphertext.isEmpty else {
            return .failure(.invalidInput("Ciphertext cannot be empty"))
        }

        var plaintext = Data(count: ciphertext.count)
        var plaintextLength = plaintext.count

        let result: ecliptix_result_t = ciphertext.withUnsafeBytes { ciphertextBytes in
            plaintext.withUnsafeMutableBytes { plaintextBytes in
                ecliptix_client_decrypt(
                    ciphertextBytes.bindMemory(to: UInt8.self).baseAddress,
                    ciphertext.count,
                    plaintextBytes.bindMemory(to: UInt8.self).baseAddress,
                    &plaintextLength
                )
            }
        }

        guard result.rawValue == 0 else {
            let errorMessage = getErrorMessage()
            Log.error("[CertificatePinning] RSA decryption failed: \(errorMessage)")
            return .failure(.decryptionFailed(errorMessage))
        }

        plaintext = plaintext.prefix(plaintextLength)

        Log.debug("[CertificatePinning] Decrypted \(ciphertext.count) bytes → \(plaintext.count) bytes")
        return .success(plaintext)
    }

    public func getPublicKey() -> Result<Data, CertificatePinningError> {
        guard isInitialized else {
            return .failure(.notInitialized)
        }

        var publicKey = Data(count: 512)
        var publicKeyLength = publicKey.count

        let result: ecliptix_result_t = publicKey.withUnsafeMutableBytes { keyBytes in
            ecliptix_client_get_public_key(
                keyBytes.bindMemory(to: UInt8.self).baseAddress,
                &publicKeyLength
            )
        }

        guard result.rawValue == 0 else {
            let errorMessage = getErrorMessage()
            Log.error("[CertificatePinning] Failed to get public key: \(errorMessage)")
            return .failure(.publicKeyError(errorMessage))
        }

        publicKey = publicKey.prefix(publicKeyLength)

        Log.info("[CertificatePinning] Retrieved public key (\(publicKey.count) bytes)")
        return .success(publicKey)
    }

    private func getErrorMessage() -> String {
        guard let errorPtr = ecliptix_client_get_error() else {
            return "Unknown error"
        }
        return String(cString: errorPtr)
    }
}

public enum CertificatePinningError: Error, CustomStringConvertible {
    case notInitialized
    case initializationFailed(String)
    case invalidInput(String)
    case verificationError(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case publicKeyError(String)

    public var description: String {
        switch self {
        case .notInitialized:
            return "Certificate pinning not initialized. Call initialize() first."
        case .initializationFailed(let message):
            return "Initialization failed: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .verificationError(let message):
            return "Verification error: \(message)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .publicKeyError(let message):
            return "Public key error: \(message)"
        }
    }
}

public enum CertificatePinningConstants {

    public static let rsaMaxPlaintextSize = 120

    public static let rsaEncryptedSize = 256

    public static let ed25519SignatureSize = 64

    public static let rsaPublicKeySize = 294
}
