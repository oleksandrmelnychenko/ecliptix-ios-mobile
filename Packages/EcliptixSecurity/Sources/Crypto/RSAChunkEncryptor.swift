import Foundation
import Security
import EcliptixCore

// MARK: - RSA Chunk Encryptor
/// Encrypts/decrypts large data in RSA chunks (migrated from C# RsaChunkEncryptor.cs)
/// Uses the server's public key from certificate pinning for encryption
public final class RSAChunkEncryptor {

    private let certificatePinningService: CertificatePinningService?

    public init(certificatePinningService: CertificatePinningService? = nil) {
        self.certificatePinningService = certificatePinningService
    }

    // MARK: - Encrypt In Chunks
    /// Encrypts data in RSA chunks
    /// Migrated from: Ecliptix.Core.Infrastructure.Security.Crypto.RsaChunkEncryptor.EncryptInChunks()
    public func encryptInChunks(data: Data) -> Result<Data, ServiceFailure> {
        guard let pinningService = certificatePinningService else {
            return .failure(.networkError("Certificate pinning service not configured"))
        }

        let chunkSize = CryptographicConstants.RSA.maxChunkSize
        let encryptedChunkSize = CryptographicConstants.RSA.encryptedChunkSize

        let chunkCount = (data.count + chunkSize - 1) / chunkSize
        var combinedEncryptedPayload = Data(capacity: chunkCount * encryptedChunkSize)

        var offset = 0
        while offset < data.count {
            let chunkLength = min(chunkSize, data.count - offset)
            let chunk = data.subdata(in: offset..<(offset + chunkLength))

            let encryptResult = pinningService.encrypt(chunk)

            switch encryptResult {
            case .failure(let error):
                return .failure(.secureStoreEncryptionFailed("RSA encryption failed: \(error.localizedDescription)"))
            case .success(let encryptedChunk):
                combinedEncryptedPayload.append(encryptedChunk)
            }

            offset += chunkSize
        }

        return .success(combinedEncryptedPayload)
    }

    // MARK: - Decrypt In Chunks
    /// Decrypts RSA-encrypted chunks
    /// Migrated from: Ecliptix.Core.Infrastructure.Security.Crypto.RsaChunkEncryptor.DecryptInChunks()
    public func decryptInChunks(data: Data) -> Result<Data, ServiceFailure> {
        guard let pinningService = certificatePinningService else {
            return .failure(.networkError("Certificate pinning service not configured"))
        }

        let encryptedChunkSize = CryptographicConstants.RSA.encryptedChunkSize
        let maxChunkSize = CryptographicConstants.RSA.maxChunkSize

        let chunkCount = (data.count + encryptedChunkSize - 1) / encryptedChunkSize
        var decryptedData = Data(capacity: chunkCount * maxChunkSize)

        var offset = 0
        var chunkNumber = 1

        while offset < data.count {
            let chunkLength = min(encryptedChunkSize, data.count - offset)
            let encryptedChunk = data.subdata(in: offset..<(offset + chunkLength))

            let decryptResult = pinningService.decrypt(encryptedChunk)

            switch decryptResult {
            case .failure(let error):
                return .failure(.secureStoreDecryptionFailed("Failed to decrypt response chunk \(chunkNumber): \(error.localizedDescription)"))
            case .success(let decryptedChunk):
                decryptedData.append(decryptedChunk)
            }

            offset += encryptedChunkSize
            chunkNumber += 1
        }

        return .success(decryptedData)
    }
}

// MARK: - Certificate Pinning Service Protocol
/// Protocol for certificate pinning and RSA operations
/// This will be implemented with iOS Security framework (SecKey, SecTrust)
public protocol CertificatePinningService {
    /// Encrypts data using the server's RSA public key
    func encrypt(_ data: Data) -> Result<Data, SecurityError>

    /// Decrypts data using the client's private key (typically not used for server responses)
    func decrypt(_ data: Data) -> Result<Data, SecurityError>

    /// Validates a server certificate against pinned certificates
    func validateServerTrust(_ trust: SecTrust, domain: String) -> Bool
}

// MARK: - Default Certificate Pinning Implementation
/// iOS implementation of certificate pinning using Security framework
/// This is a placeholder - full implementation would include actual pinned certificates
public final class DefaultCertificatePinningService: CertificatePinningService {

    private let pinnedCertificates: [Data]
    private var serverPublicKey: SecKey?

    public init(pinnedCertificates: [Data] = []) {
        self.pinnedCertificates = pinnedCertificates
    }

    // MARK: - Set Server Public Key
    public func setServerPublicKey(_ publicKey: SecKey) {
        self.serverPublicKey = publicKey
    }

    public func setServerPublicKey(from data: Data) throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            if let error = error {
                throw SecurityError.keyGenerationFailed
            }
            throw SecurityError.invalidKey
        }

        self.serverPublicKey = publicKey
    }

    // MARK: - Encrypt
    public func encrypt(_ data: Data) -> Result<Data, SecurityError> {
        guard let publicKey = serverPublicKey else {
            return .failure(.invalidKey)
        }

        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionPKCS1,
            data as CFData,
            &error
        ) as Data? else {
            return .failure(.encryptionFailed)
        }

        return .success(encryptedData)
    }

    // MARK: - Decrypt
    public func decrypt(_ data: Data) -> Result<Data, SecurityError> {
        // Decryption typically requires the private key
        // For client-side, we usually don't decrypt server responses
        // This is here for completeness
        return .failure(.invalidKey)
    }

    // MARK: - Validate Server Trust
    public func validateServerTrust(_ trust: SecTrust, domain: String) -> Bool {
        // Evaluate the trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        guard isValid else {
            return false
        }

        // If we have pinned certificates, validate against them
        if !pinnedCertificates.isEmpty {
            return validatePinnedCertificates(trust)
        }

        return true
    }

    // MARK: - Validate Pinned Certificates
    private func validatePinnedCertificates(_ trust: SecTrust) -> Bool {
        guard let serverCertificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            return false
        }

        let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data

        // Check if server certificate matches any pinned certificate
        return pinnedCertificates.contains { pinnedCertData in
            return serverCertificateData == pinnedCertData
        }
    }
}
