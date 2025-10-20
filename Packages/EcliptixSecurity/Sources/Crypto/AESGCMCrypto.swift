import Foundation
import Crypto
import EcliptixCore

// MARK: - AES-GCM Cryptographic Service
/// Provides AES-GCM encryption and decryption (migrated from C# AesGcm usage in EcliptixProtocolSystem.cs)
public final class AESGCMCrypto: CryptographicService {

    public init() {}

    // MARK: - Encrypt with ChaCha20-Poly1305
    /// Note: CryptoKit uses ChaChaPoly by default, but for compatibility with desktop we use AES.GCM
    public func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        // For iOS we can use AES.GCM which is hardware-accelerated
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        // Combine nonce + ciphertext + tag (same format as C#)
        var result = Data()
        result.append(contentsOf: sealedBox.nonce)
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)

        return result
    }

    // MARK: - Decrypt with ChaCha20-Poly1305
    public func decrypt(data: Data, key: SymmetricKey) throws -> Data {
        // Extract nonce (12 bytes), ciphertext, and tag (16 bytes)
        guard data.count > CryptographicConstants.aesGcmNonceSize + CryptographicConstants.aesGcmTagSize else {
            throw SecurityError.invalidData
        }

        let nonceData = data.prefix(CryptographicConstants.aesGcmNonceSize)
        let tag = data.suffix(CryptographicConstants.aesGcmTagSize)
        let ciphertext = data.dropFirst(CryptographicConstants.aesGcmNonceSize).dropLast(CryptographicConstants.aesGcmTagSize)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)

        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Encrypt with explicit nonce and associated data
    /// Encrypts data with a specific nonce and associated data (for envelope encryption)
    /// Migrated from: Ecliptix.Protocol.System.Core.EcliptixProtocolSystem.Encrypt()
    public func encryptWithNonceAndAD(
        plaintext: Data,
        key: Data,
        nonce: Data,
        associatedData: Data
    ) throws -> Data {
        guard key.count == CryptographicConstants.aesKeySize else {
            throw SecurityError.invalidKey
        }

        guard nonce.count == CryptographicConstants.aesGcmNonceSize else {
            throw SecurityError.invalidData
        }

        let symmetricKey = SymmetricKey(data: key)
        let aesNonce = try AES.GCM.Nonce(data: nonce)

        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: symmetricKey,
            nonce: aesNonce,
            authenticating: associatedData
        )

        // Return ciphertext + tag (C# format: Buffer.BlockCopy(ciphertext, 0, result, 0, ciphertext.Length); tag.CopyTo(result.AsSpan(ciphertext.Length)))
        var result = Data()
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)

        return result
    }

    // MARK: - Decrypt with explicit nonce and associated data
    /// Decrypts data with a specific nonce and associated data (for envelope decryption)
    /// Migrated from: Ecliptix.Protocol.System.Core.EcliptixProtocolSystem.DecryptFromMaterials()
    public func decryptWithNonceAndAD(
        encryptedData: Data,
        key: Data,
        nonce: Data,
        associatedData: Data
    ) throws -> Data {
        guard key.count == CryptographicConstants.aesKeySize else {
            throw SecurityError.invalidKey
        }

        guard nonce.count == CryptographicConstants.aesGcmNonceSize else {
            throw SecurityError.invalidData
        }

        // Extract ciphertext and tag
        // C#: int cipherLength = fullCipherSpan.Length - tagSize;
        let tagSize = CryptographicConstants.aesGcmTagSize
        let cipherLength = encryptedData.count - tagSize

        guard cipherLength >= 0 else {
            throw SecurityError.invalidData
        }

        let ciphertext = encryptedData.prefix(cipherLength)
        let tag = encryptedData.suffix(tagSize)

        let symmetricKey = SymmetricKey(data: key)
        let aesNonce = try AES.GCM.Nonce(data: nonce)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: aesNonce,
            ciphertext: ciphertext,
            tag: tag
        )

        return try AES.GCM.open(sealedBox, using: symmetricKey, authenticating: associatedData)
    }

    // MARK: - Generate Symmetric Key
    public func generateSymmetricKey(size: SymmetricKeySize) -> SymmetricKey {
        return SymmetricKey(size: size)
    }

    // MARK: - Generate Nonce
    public func generateNonce() -> Data {
        return Data(AES.GCM.Nonce())
    }
}

// MARK: - Cryptographic Helpers
public struct CryptographicHelpers {

    /// Computes SHA256 fingerprint of data (migrated from CryptographicHelpers.cs)
    public static func computeSHA256Fingerprint(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        let fingerprintLength = CryptographicConstants.hashFingerprintLength
        return String(hashString.prefix(fingerprintLength))
    }

    /// Generates a secure random nonce
    public static func generateRandomNonce(size: Int = CryptographicConstants.aesGcmNonceSize) -> Data {
        var bytes = Data(count: size)
        _ = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, size, buffer.baseAddress!)
        }
        return bytes
    }

    /// Generates secure random bytes
    public static func generateRandomBytes(count: Int) -> Data {
        var bytes = Data(count: count)
        _ = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        return bytes
    }

    /// Constant-time byte array comparison (for security-sensitive comparisons)
    public static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else {
            return false
        }

        var result: UInt8 = 0
        for i in 0..<a.count {
            result |= a[i] ^ b[i]
        }

        return result == 0
    }

    /// Securely wipes data from memory (best effort in Swift)
    public static func secureWipe(_ data: inout Data) {
        data.resetBytes(in: 0..<data.count)
        data = Data()
    }
}
