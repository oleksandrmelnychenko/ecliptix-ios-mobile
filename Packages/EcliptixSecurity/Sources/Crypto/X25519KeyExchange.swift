import Crypto
import EcliptixCore
import Foundation

public final class X25519KeyExchange: KeyExchangeService {

    public init() {}
    public func generateKeyPair() -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Curve25519.KeyAgreement.PublicKey) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        return (privateKey, publicKey)
    }
    public func performKeyAgreement(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        publicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SharedSecret {
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }

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

        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyBytes)

        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKeyBytes)

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)

        return sharedSecret.withUnsafeBytes { Data($0) }
    }
    public func generatePublicKey(from privateKey: Curve25519.KeyAgreement.PrivateKey) -> Curve25519.KeyAgreement.PublicKey {
        return privateKey.publicKey
    }

    public func privateKeyToBytes(_ privateKey: Curve25519.KeyAgreement.PrivateKey) -> Data {
        return privateKey.rawRepresentation
    }

    public func publicKeyToBytes(_ publicKey: Curve25519.KeyAgreement.PublicKey) -> Data {
        return publicKey.rawRepresentation
    }

    public func privateKeyFromBytes(_ bytes: Data) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard bytes.count == CryptographicConstants.x25519PrivateKeySize else {
            throw SecurityError.invalidKey
        }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)
    }

    public func publicKeyFromBytes(_ bytes: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        guard bytes.count == CryptographicConstants.x25519PublicKeySize else {
            throw SecurityError.invalidKey
        }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes)
    }
}

public struct HKDFKeyDerivation {

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

    public static func deriveChainAndMessageKey(
        from chainKey: Data,
        msgInfo: [UInt8] = CryptographicConstants.msgInfo,
        chainInfo: [UInt8] = CryptographicConstants.chainInfo
    ) throws -> (messageKey: Data, nextChainKey: Data) {
        guard chainKey.count == CryptographicConstants.x25519KeySize else {
            throw SecurityError.invalidKey
        }

        let messageKey = try deriveKey(
            inputKeyMaterial: chainKey,
            salt: nil,
            info: Data(msgInfo),
            outputByteCount: CryptographicConstants.aesKeySize
        )

        let nextChainKey = try deriveKey(
            inputKeyMaterial: chainKey,
            salt: nil,
            info: Data(chainInfo),
            outputByteCount: CryptographicConstants.x25519KeySize
        )

        return (messageKey, nextChainKey)
    }

    public static func deriveRootAndChainKeys(
        from dhOutput: Data,
        info: String = CryptographicConstants.x3dhInfo
    ) throws -> (rootKey: Data, chainKey: Data) {
        let infoData = Data(info.utf8)

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
