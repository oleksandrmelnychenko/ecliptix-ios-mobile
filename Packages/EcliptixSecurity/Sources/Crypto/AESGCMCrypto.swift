import Crypto
import EcliptixCore
import Foundation

public final class AESGCMCrypto: CryptographicService, @unchecked Sendable {

    public init() {}

    public func encrypt(data: Data, key: SymmetricKey) throws -> Data {

        let nonce = try generateSecureNonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        var result = Data()
        result.append(contentsOf: sealedBox.nonce)
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)

        return result
    }

    private func generateSecureNonce() throws -> AES.GCM.Nonce {
        var nonceBytes = Data(count: CryptographicConstants.aesGcmNonceSize)
        let result: Int32 = nonceBytes.withUnsafeMutableBytes { buffer in
            guard let ptr = buffer.baseAddress else { return -1 }
            return SecRandomCopyBytes(kSecRandomDefault, CryptographicConstants.aesGcmNonceSize, ptr)
        }

        guard result == errSecSuccess else {
            throw SecurityError.encryptionFailed
        }

        let entropy = EntropyValidator.shannonEntropy(of: nonceBytes)
        guard entropy >= 7.0 else {
            Log.warning("[AESGCMCrypto] Generated nonce has low entropy: \(entropy), regenerating...")
            return try generateSecureNonce()
        }

        return try AES.GCM.Nonce(data: nonceBytes)
    }
    public func decrypt(data: Data, key: SymmetricKey) throws -> Data {

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

        var result = Data()
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)

        return result
    }

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
    public func generateSymmetricKey(size: SymmetricKeySize) -> SymmetricKey {
        return SymmetricKey(size: size)
    }
    public func generateNonce() -> Data {
        return Data(AES.GCM.Nonce())
    }
}
public struct CryptographicHelpers {

    public static func computeSHA256Fingerprint(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        let fingerprintLength = CryptographicConstants.hashFingerprintLength
        return String(hashString.prefix(fingerprintLength))
    }

    public static func generateRandomNonce(size: Int = CryptographicConstants.aesGcmNonceSize) -> Data {
        var bytes = Data(count: size)
        _ = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, size, buffer.baseAddress!)
        }
        return bytes
    }

    public static func generateRandomBytes(count: Int) -> Data {
        var bytes = Data(count: count)
        _ = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        return bytes
    }

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

    public static func secureWipe(_ data: inout Data) {
        data.resetBytes(in: 0..<data.count)
        data = Data()
    }
}
