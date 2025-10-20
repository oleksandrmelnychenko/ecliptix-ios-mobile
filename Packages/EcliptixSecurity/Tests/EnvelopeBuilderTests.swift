import XCTest
import Crypto
@testable import EcliptixSecurity
@testable import EcliptixCore

final class EnvelopeBuilderTests: XCTestCase {

    // MARK: - Test Create Envelope Metadata
    func testCreateEnvelopeMetadata() {
        let requestId: UInt32 = 12345
        let nonce = CryptographicHelpers.generateRandomNonce()
        let ratchetIndex: UInt32 = 10

        let metadata = EnvelopeBuilder.createEnvelopeMetadata(
            requestId: requestId,
            nonce: nonce,
            ratchetIndex: ratchetIndex,
            envelopeType: .request
        )

        XCTAssertEqual(metadata.envelopeId, "12345")
        XCTAssertEqual(metadata.nonce, nonce)
        XCTAssertEqual(metadata.ratchetIndex, ratchetIndex)
        XCTAssertEqual(metadata.envelopeType, .request)
        XCTAssertEqual(metadata.channelKeyId.count, 16) // Should be 16 bytes
    }

    // MARK: - Test Parse Result Code
    func testParseResultCode() {
        // Create result code bytes (Int32 in little endian)
        var resultCodeValue = Int32(EnvelopeResultCode.success.rawValue)
        var resultCodeBytes = Data(count: 4)
        resultCodeBytes.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: resultCodeValue.littleEndian, as: Int32.self)
        }

        let result = EnvelopeBuilder.parseResultCode(from: resultCodeBytes)

        XCTAssertTrue(result.isSuccess)
        if case .success(let code) = result {
            XCTAssertEqual(code, .success)
        }
    }

    // MARK: - Test Extract Request ID
    func testExtractRequestId() {
        let envelopeId = "99999"
        let requestId = EnvelopeBuilder.extractRequestId(from: envelopeId)

        XCTAssertEqual(requestId, 99999)
    }

    func testExtractRequestIdWithInvalidString() {
        let envelopeId = "invalid"
        let requestId = EnvelopeBuilder.extractRequestId(from: envelopeId)

        // Should return a random UInt32
        XCTAssertGreaterThan(requestId, 0)
    }

    // MARK: - Test Metadata Encryption/Decryption
    func testMetadataEncryptionDecryption() throws {
        // Create test metadata
        let metadata = EnvelopeBuilder.createEnvelopeMetadata(
            requestId: 123,
            nonce: CryptographicHelpers.generateRandomNonce(),
            ratchetIndex: 5,
            envelopeType: .request
        )

        // Generate encryption key and nonce
        let headerKey = CryptographicHelpers.generateRandomBytes(count: CryptographicConstants.aesKeySize)
        let headerNonce = CryptographicHelpers.generateRandomNonce()
        let associatedData = Data("test-associated-data".utf8)

        // Encrypt metadata
        let encryptResult = EnvelopeBuilder.encryptMetadata(
            metadata: metadata,
            headerEncryptionKey: headerKey,
            headerNonce: headerNonce,
            associatedData: associatedData
        )

        XCTAssertTrue(encryptResult.isSuccess)
        guard case .success(let encryptedMetadata) = encryptResult else {
            XCTFail("Encryption failed")
            return
        }

        // Verify encrypted data has correct size (ciphertext + 16-byte tag)
        XCTAssertGreaterThan(encryptedMetadata.count, 16)

        // Decrypt metadata
        let decryptResult = EnvelopeBuilder.decryptMetadata(
            encryptedMetadata: encryptedMetadata,
            headerEncryptionKey: headerKey,
            headerNonce: headerNonce,
            associatedData: associatedData
        )

        XCTAssertTrue(decryptResult.isSuccess)
        guard case .success(let decryptedMetadata) = decryptResult else {
            XCTFail("Decryption failed")
            return
        }

        // Verify decrypted metadata matches original
        XCTAssertEqual(decryptedMetadata.envelopeId, metadata.envelopeId)
        XCTAssertEqual(decryptedMetadata.ratchetIndex, metadata.ratchetIndex)
        XCTAssertEqual(decryptedMetadata.envelopeType, metadata.envelopeType)
        XCTAssertEqual(decryptedMetadata.nonce, metadata.nonce)
    }

    // MARK: - Test Metadata Decryption with Wrong Key
    func testMetadataDecryptionWithWrongKey() throws {
        let metadata = EnvelopeBuilder.createEnvelopeMetadata(
            requestId: 123,
            nonce: CryptographicHelpers.generateRandomNonce(),
            ratchetIndex: 5,
            envelopeType: .request
        )

        let headerKey = CryptographicHelpers.generateRandomBytes(count: CryptographicConstants.aesKeySize)
        let headerNonce = CryptographicHelpers.generateRandomNonce()
        let associatedData = Data("test-associated-data".utf8)

        // Encrypt
        let encryptResult = EnvelopeBuilder.encryptMetadata(
            metadata: metadata,
            headerEncryptionKey: headerKey,
            headerNonce: headerNonce,
            associatedData: associatedData
        )

        guard case .success(let encryptedMetadata) = encryptResult else {
            XCTFail("Encryption should succeed")
            return
        }

        // Try to decrypt with wrong key
        let wrongKey = CryptographicHelpers.generateRandomBytes(count: CryptographicConstants.aesKeySize)

        let decryptResult = EnvelopeBuilder.decryptMetadata(
            encryptedMetadata: encryptedMetadata,
            headerEncryptionKey: wrongKey,
            headerNonce: headerNonce,
            associatedData: associatedData
        )

        // Should fail
        XCTAssertTrue(decryptResult.isFailure)
    }

    // MARK: - Test Create Secure Envelope
    func testCreateSecureEnvelope() throws {
        let metadata = EnvelopeBuilder.createEnvelopeMetadata(
            requestId: 456,
            nonce: CryptographicHelpers.generateRandomNonce(),
            ratchetIndex: 3,
            envelopeType: .response
        )

        let encryptedPayload = Data("encrypted-payload-data".utf8)
        let headerNonce = CryptographicHelpers.generateRandomNonce()

        let envelope = try EnvelopeBuilder.createSecureEnvelope(
            metadata: metadata,
            encryptedPayload: encryptedPayload,
            headerNonce: headerNonce,
            dhPublicKey: nil
        )

        XCTAssertEqual(envelope.encryptedPayload, encryptedPayload)
        XCTAssertEqual(envelope.headerNonce, headerNonce)
        XCTAssertEqual(envelope.resultCode.count, 4)

        // Verify result code is success (0)
        let resultCodeValue = envelope.resultCode.withUnsafeBytes { buffer in
            buffer.load(as: Int32.self).littleEndian
        }
        XCTAssertEqual(resultCodeValue, 0)
    }
}
