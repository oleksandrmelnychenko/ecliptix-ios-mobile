import Foundation
import Crypto
import EcliptixCore

// MARK: - Envelope Builder
/// Utilities for creating, encrypting, and parsing secure envelopes
/// Migrated from: Ecliptix.Protocol.System.Utilities.EnvelopeBuilder.cs
public struct EnvelopeBuilder {

    // MARK: - Create Envelope Metadata
    /// Creates envelope metadata for a request or response
    /// Migrated from: EnvelopeBuilder.CreateEnvelopeMetadata()
    public static func createEnvelopeMetadata(
        requestId: UInt32,
        nonce: Data,
        ratchetIndex: UInt32,
        channelKeyId: Data? = nil,
        envelopeType: EnvelopeType = .request,
        correlationId: String? = nil
    ) -> EnvelopeMetadata {
        let keyId = channelKeyId ?? generateChannelKeyId()

        return EnvelopeMetadata(
            envelopeId: String(requestId),
            channelKeyId: keyId,
            nonce: nonce,
            ratchetIndex: ratchetIndex,
            envelopeType: envelopeType,
            correlationId: correlationId
        )
    }

    // MARK: - Create Secure Envelope
    /// Creates a secure envelope with encrypted payload and metadata
    /// Migrated from: EnvelopeBuilder.CreateSecureEnvelope()
    public static func createSecureEnvelope(
        metadata: EnvelopeMetadata,
        encryptedPayload: Data,
        timestamp: Date? = nil,
        authenticationTag: Data? = nil,
        resultCode: EnvelopeResultCode = .success,
        errorDetails: Data? = nil,
        headerNonce: Data,
        dhPublicKey: Data? = nil
    ) throws -> SecureEnvelope {
        // Serialize metadata to binary
        let metadataData = try metadata.toData()

        // Convert result code to 4-byte Data (Int32)
        let resultCodeValue = Int32(resultCode.rawValue)
        var resultCodeBytes = Data(count: 4)
        resultCodeBytes.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: resultCodeValue.littleEndian, as: Int32.self)
        }

        return SecureEnvelope(
            metaData: metadataData,
            encryptedPayload: encryptedPayload,
            resultCode: resultCodeBytes,
            authenticationTag: authenticationTag,
            timestamp: timestamp ?? Date(),
            errorDetails: errorDetails,
            headerNonce: headerNonce,
            dhPublicKey: dhPublicKey
        )
    }

    // MARK: - Parse Envelope Metadata
    /// Parses envelope metadata from binary data
    /// Migrated from: EnvelopeBuilder.ParseEnvelopeMetadata()
    public static func parseEnvelopeMetadata(
        from metaDataBytes: Data
    ) -> Result<EnvelopeMetadata, ProtocolFailure> {
        do {
            let metadata = try EnvelopeMetadata.fromData(metaDataBytes)
            return .success(metadata)
        } catch {
            return .failure(.decode("Failed to parse EnvelopeMetadata: \(error.localizedDescription)"))
        }
    }

    // MARK: - Parse Result Code
    /// Parses result code from 4-byte Data
    /// Migrated from: EnvelopeBuilder.ParseResultCode()
    public static func parseResultCode(
        from resultCodeBytes: Data
    ) -> Result<EnvelopeResultCode, ProtocolFailure> {
        guard resultCodeBytes.count == 4 else {
            return .failure(.decode("Invalid result code length: expected 4 bytes, got \(resultCodeBytes.count)"))
        }

        let resultCodeValue = resultCodeBytes.withUnsafeBytes { buffer in
            buffer.load(as: Int32.self).littleEndian
        }

        guard let resultCode = EnvelopeResultCode(rawValue: resultCodeValue) else {
            return .failure(.decode("Unknown result code value: \(resultCodeValue)"))
        }

        return .success(resultCode)
    }

    // MARK: - Extract Request ID
    /// Extracts request ID from envelope ID string
    /// Migrated from: EnvelopeBuilder.ExtractRequestIdFromEnvelopeId()
    public static func extractRequestId(from envelopeId: String) -> UInt32 {
        if let requestId = UInt32(envelopeId) {
            return requestId
        }

        // Fallback: generate random UInt32
        return generateRandomUInt32()
    }

    // MARK: - Encrypt Metadata
    /// Encrypts envelope metadata using AES-GCM
    /// Migrated from: EnvelopeBuilder.EncryptMetadata()
    public static func encryptMetadata(
        metadata: EnvelopeMetadata,
        headerEncryptionKey: Data,
        headerNonce: Data,
        associatedData: Data
    ) -> Result<Data, ProtocolFailure> {
        do {
            // Serialize metadata to bytes
            let metadataBytes = try metadata.toData()

            // Encrypt using AES-GCM with associated data
            guard headerEncryptionKey.count == CryptographicConstants.aesKeySize else {
                return .failure(.generic("Invalid header encryption key size"))
            }

            guard headerNonce.count == CryptographicConstants.aesGcmNonceSize else {
                return .failure(.generic("Invalid header nonce size"))
            }

            let symmetricKey = SymmetricKey(data: headerEncryptionKey)
            let nonce = try AES.GCM.Nonce(data: headerNonce)

            let sealedBox = try AES.GCM.seal(
                metadataBytes,
                using: symmetricKey,
                nonce: nonce,
                authenticating: associatedData
            )

            // Combine ciphertext + tag (C# format)
            var result = Data()
            result.append(sealedBox.ciphertext)
            result.append(sealedBox.tag)

            return .success(result)
        } catch {
            return .failure(.generic("Failed to encrypt metadata: \(error.localizedDescription)"))
        }
    }

    // MARK: - Decrypt Metadata
    /// Decrypts envelope metadata using AES-GCM
    /// Migrated from: EnvelopeBuilder.DecryptMetadata()
    public static func decryptMetadata(
        encryptedMetadata: Data,
        headerEncryptionKey: Data,
        headerNonce: Data,
        associatedData: Data
    ) -> Result<EnvelopeMetadata, ProtocolFailure> {
        do {
            // Split into ciphertext and tag
            let tagSize = CryptographicConstants.aesGcmTagSize
            let cipherLength = encryptedMetadata.count - tagSize

            guard cipherLength >= 0 else {
                return .failure(.bufferTooSmall("Encrypted metadata too small"))
            }

            let ciphertext = encryptedMetadata.prefix(cipherLength)
            let tag = encryptedMetadata.suffix(tagSize)

            // Decrypt using AES-GCM
            guard headerEncryptionKey.count == CryptographicConstants.aesKeySize else {
                return .failure(.generic("Invalid header encryption key size"))
            }

            guard headerNonce.count == CryptographicConstants.aesGcmNonceSize else {
                return .failure(.generic("Invalid header nonce size"))
            }

            let symmetricKey = SymmetricKey(data: headerEncryptionKey)
            let nonce = try AES.GCM.Nonce(data: headerNonce)

            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag
            )

            let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey, authenticating: associatedData)

            // Parse metadata
            let metadata = try EnvelopeMetadata.fromData(plaintext)
            return .success(metadata)
        } catch let error as CryptoKitError {
            return .failure(.generic("Header authentication failed: \(error.localizedDescription)"))
        } catch {
            return .failure(.generic("Failed to decrypt metadata: \(error.localizedDescription)"))
        }
    }

    // MARK: - Generate Channel Key ID
    /// Generates a random 16-byte channel key ID
    private static func generateChannelKeyId() -> Data {
        return CryptographicHelpers.generateRandomBytes(count: 16)
    }

    // MARK: - Generate Random UInt32
    private static func generateRandomUInt32() -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        return value
    }
}

// MARK: - Envelope Builder Extensions
public extension EnvelopeBuilder {

    /// Creates a request envelope with encryption
    static func createRequestEnvelope(
        requestId: UInt32,
        payload: Data,
        messageKey: Data,
        headerKey: Data,
        nonce: Data,
        headerNonce: Data,
        ratchetIndex: UInt32,
        channelKeyId: Data? = nil,
        dhPublicKey: Data? = nil,
        associatedData: Data
    ) -> Result<SecureEnvelope, ProtocolFailure> {
        do {
            // Create metadata
            let metadata = createEnvelopeMetadata(
                requestId: requestId,
                nonce: nonce,
                ratchetIndex: ratchetIndex,
                channelKeyId: channelKeyId,
                envelopeType: .request
            )

            // Encrypt payload
            let crypto = AESGCMCrypto()
            let encryptedPayload = try crypto.encryptWithNonceAndAD(
                plaintext: payload,
                key: messageKey,
                nonce: nonce,
                associatedData: associatedData
            )

            // Encrypt metadata
            let encryptedMetadataResult = encryptMetadata(
                metadata: metadata,
                headerEncryptionKey: headerKey,
                headerNonce: headerNonce,
                associatedData: associatedData
            )

            guard case .success(let encryptedMetadata) = encryptedMetadataResult else {
                if case .failure(let error) = encryptedMetadataResult {
                    return .failure(error)
                }
                return .failure(.generic("Failed to encrypt metadata"))
            }

            // Create secure envelope
            let envelope = try createSecureEnvelope(
                metadata: metadata,
                encryptedPayload: encryptedPayload,
                headerNonce: headerNonce,
                dhPublicKey: dhPublicKey
            )

            // Replace metadata with encrypted version
            var finalEnvelope = envelope
            finalEnvelope.metaData = encryptedMetadata

            return .success(finalEnvelope)
        } catch {
            return .failure(.generic("Failed to create request envelope: \(error.localizedDescription)"))
        }
    }

    /// Decrypts and parses a response envelope
    static func decryptResponseEnvelope(
        envelope: SecureEnvelope,
        messageKey: Data,
        headerKey: Data,
        associatedData: Data
    ) -> Result<(metadata: EnvelopeMetadata, payload: Data, resultCode: EnvelopeResultCode), ProtocolFailure> {
        do {
            // Decrypt metadata
            let metadataResult = decryptMetadata(
                encryptedMetadata: envelope.metaData,
                headerEncryptionKey: headerKey,
                headerNonce: envelope.headerNonce,
                associatedData: associatedData
            )

            guard case .success(let metadata) = metadataResult else {
                if case .failure(let error) = metadataResult {
                    return .failure(error)
                }
                return .failure(.generic("Failed to decrypt metadata"))
            }

            // Parse result code
            let resultCodeResult = parseResultCode(from: envelope.resultCode)
            guard case .success(let resultCode) = resultCodeResult else {
                if case .failure(let error) = resultCodeResult {
                    return .failure(error)
                }
                return .failure(.generic("Failed to parse result code"))
            }

            // Decrypt payload
            let crypto = AESGCMCrypto()
            let plainPayload = try crypto.decryptWithNonceAndAD(
                encryptedData: envelope.encryptedPayload,
                key: messageKey,
                nonce: metadata.nonce,
                associatedData: associatedData
            )

            return .success((metadata, plainPayload, resultCode))
        } catch {
            return .failure(.generic("Failed to decrypt response envelope: \(error.localizedDescription)"))
        }
    }
}
