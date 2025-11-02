import EcliptixCertificatePinning
import EcliptixCore
import Foundation

/// Service for RSA-based encryption operations in the protocol layer
/// Migrated from: Ecliptix.Core.Infrastructure.Network.Core.Providers.NetworkProvider (RSA encryption parts)
public final class RSAEncryptionService {

    private let certificatePinningClient: CertificatePinningClient
    private var isInitialized: Bool = false

    /// Creates RSA encryption service
    /// - Parameter certificatePinningClient: Certificate pinning client for RSA operations
    public init(certificatePinningClient: CertificatePinningClient) {
        self.certificatePinningClient = certificatePinningClient
    }

    /// Initializes the RSA encryption service
    /// - Returns: Result indicating success or failure
    public func initialize() -> Result<Void, ServiceFailure> {
        guard !isInitialized else {
            return .success(())
        }

        let initResult = certificatePinningClient.initialize()

        switch initResult {
        case .success:
            isInitialized = true
            Log.info("[RSAEncryption] [OK] Service initialized")
            return .success(())

        case .failure(let error):
            Log.error("[RSAEncryption] Initialization failed: \(error)")
            return .failure(.secureStoreEncryptionFailed(error.description))
        }
    }

    /// Encrypts public key exchange data for protocol initialization
    /// - Parameter data: Public key exchange data to encrypt
    /// - Returns: Result with RSA-encrypted data or error
    /// - Note: Used during protocol establishment for secure key exchange
    public func encryptPublicKeyExchange(data: Data) -> Result<Data, ServiceFailure> {
        guard isInitialized else {
            return .failure(.secureStoreEncryptionFailed("RSA encryption service not initialized"))
        }

        guard !data.isEmpty else {
            return .failure(.invalidData("Public key exchange data cannot be empty"))
        }

        // Use chunk encryption for large public key exchange payloads
        let encryptResult = RSAChunkEncryptor.encryptInChunks(
            certificatePinningClient: certificatePinningClient,
            originalData: data
        )

        switch encryptResult {
        case .success(let encryptedData):
            Log.info("[RSAEncryption] Encrypted public key exchange: \(data.count) → \(encryptedData.count) bytes")
            return .success(encryptedData)

        case .failure(let error):
            Log.error("[RSAEncryption] Public key exchange encryption failed: \(error)")
            return .failure(.secureStoreEncryptionFailed(error.description))
        }
    }

    /// Decrypts RSA-encrypted public key exchange response
    /// - Parameter encryptedData: RSA-encrypted response from server
    /// - Returns: Result with decrypted public key exchange data or error
    public func decryptPublicKeyExchange(encryptedData: Data) -> Result<Data, ServiceFailure> {
        guard isInitialized else {
            return .failure(.secureStoreDecryptionFailed("RSA encryption service not initialized"))
        }

        guard !encryptedData.isEmpty else {
            return .failure(.invalidData("Encrypted data cannot be empty"))
        }

        // Use chunk decryption for large encrypted payloads
        let decryptResult = RSAChunkEncryptor.decryptInChunks(
            certificatePinningClient: certificatePinningClient,
            combinedEncryptedData: encryptedData
        )

        switch decryptResult {
        case .success(let decryptedData):
            Log.info("[RSAEncryption] Decrypted public key exchange: \(encryptedData.count) → \(decryptedData.count) bytes")
            return .success(decryptedData)

        case .failure(let error):
            Log.error("[RSAEncryption] Public key exchange decryption failed: \(error)")
            return .failure(.secureStoreDecryptionFailed(error.description))
        }
    }

    /// Verifies Ed25519 signature on server data
    /// - Parameters:
    ///   - data: Data that was signed
    ///   - signature: Ed25519 signature to verify
    /// - Returns: Result with true if signature is valid, false otherwise
    /// - Note: Used to verify server responses during protocol establishment
    public func verifyServerSignature(data: Data, signature: Data) -> Result<Bool, ServiceFailure> {
        guard isInitialized else {
            return .failure(.invalidData("RSA encryption service not initialized"))
        }

        let verifyResult = certificatePinningClient.verifySignature(data: data, signature: signature)

        switch verifyResult {
        case .success(let isValid):
            if isValid {
                Log.debug("[RSAEncryption] Server signature verified [OK]")
            } else {
                Log.warning("[RSAEncryption] Server signature verification failed [FAILED]")
            }
            return .success(isValid)

        case .failure(let error):
            Log.error("[RSAEncryption] Signature verification error: \(error)")
            return .failure(.invalidData(error.description))
        }
    }

    /// Gets client's RSA public key for transmission to server
    /// - Returns: Result with RSA public key in DER format or error
    /// - Note: This key is sent to the server during protocol initialization
    public func getClientPublicKey() -> Result<Data, ServiceFailure> {
        guard isInitialized else {
            return .failure(.invalidData("RSA encryption service not initialized"))
        }

        let keyResult = certificatePinningClient.getPublicKey()

        switch keyResult {
        case .success(let publicKey):
            Log.info("[RSAEncryption] Retrieved client public key (\(publicKey.count) bytes)")
            return .success(publicKey)

        case .failure(let error):
            Log.error("[RSAEncryption] Failed to get client public key: \(error)")
            return .failure(.invalidData(error.description))
        }
    }

    /// Cleans up RSA encryption resources
    public func cleanup() {
        guard isInitialized else { return }

        certificatePinningClient.cleanup()
        isInitialized = false
        Log.info("[RSAEncryption] Service cleaned up")
    }
}
