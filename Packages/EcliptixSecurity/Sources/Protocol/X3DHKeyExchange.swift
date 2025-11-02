import Crypto
import EcliptixCore
import Foundation

public final class X3DHKeyExchange {

    private let keyExchange: X25519KeyExchange

    public init(keyExchange: X25519KeyExchange = X25519KeyExchange()) {
        self.keyExchange = keyExchange
    }

    public func generatePreKeyBundle() throws -> PreKeyBundle {

        let (identityPrivate, identityPublic) = keyExchange.generateKeyPair()

        let (signedPreKeyPrivate, signedPreKeyPublic) = keyExchange.generateKeyPair()
        let signedPreKeyId = UInt32.random(in: 1...UInt32.max)

        let signature = try signPreKey(
            preKeyPublic: signedPreKeyPublic,
            identityPrivate: identityPrivate
        )

        let (ephemeralPrivate, ephemeralPublic) = keyExchange.generateKeyPair()

        return PreKeyBundle(
            identityPublicKey: keyExchange.publicKeyToBytes(identityPublic),
            identityPrivateKey: keyExchange.privateKeyToBytes(identityPrivate),
            signedPreKeyId: signedPreKeyId,
            signedPreKeyPublicKey: keyExchange.publicKeyToBytes(signedPreKeyPublic),
            signedPreKeyPrivateKey: keyExchange.privateKeyToBytes(signedPreKeyPrivate),
            signedPreKeySignature: signature,
            ephemeralPublicKey: keyExchange.publicKeyToBytes(ephemeralPublic),
            ephemeralPrivateKey: keyExchange.privateKeyToBytes(ephemeralPrivate)
        )
    }

    public func generatePersistentKeyBundle() throws -> PersistentKeyBundle {

        let (identityPrivate, identityPublic) = keyExchange.generateKeyPair()

        let (signedPreKeyPrivate, signedPreKeyPublic) = keyExchange.generateKeyPair()
        let signedPreKeyId = UInt32.random(in: 1...UInt32.max)

        let signature = try signPreKey(
            preKeyPublic: signedPreKeyPublic,
            identityPrivate: identityPrivate
        )

        return PersistentKeyBundle(
            identityPublicKey: keyExchange.publicKeyToBytes(identityPublic),
            identityPrivateKey: keyExchange.privateKeyToBytes(identityPrivate),
            signedPreKeyId: signedPreKeyId,
            signedPreKeyPublicKey: keyExchange.publicKeyToBytes(signedPreKeyPublic),
            signedPreKeyPrivateKey: keyExchange.privateKeyToBytes(signedPreKeyPrivate),
            signedPreKeySignature: signature
        )
    }

    public func performInitiatorKeyAgreement(
        bobsBundle: X3DHPublicKeyBundle,
        aliceIdentityPrivate: Data,
        aliceEphemeralPrivate: Data
    ) throws -> Data {

        try validatePublicKeyBundle(bobsBundle)

        let IK_A = try keyExchange.privateKeyFromBytes(aliceIdentityPrivate)
        let EK_A = try keyExchange.privateKeyFromBytes(aliceEphemeralPrivate)

        let IK_B = try keyExchange.publicKeyFromBytes(bobsBundle.identityPublicKey)
        let SPK_B = try keyExchange.publicKeyFromBytes(bobsBundle.signedPreKeyPublicKey)
        let EPK_B = try keyExchange.publicKeyFromBytes(bobsBundle.ephemeralPublicKey)

        let dh1 = try keyExchange.performKeyAgreement(privateKey: IK_A, publicKey: SPK_B)

        let dh2 = try keyExchange.performKeyAgreement(privateKey: EK_A, publicKey: IK_B)

        let dh3 = try keyExchange.performKeyAgreement(privateKey: EK_A, publicKey: SPK_B)

        let dh4 = try keyExchange.performKeyAgreement(privateKey: EK_A, publicKey: EPK_B)

        var combinedSecret = Data()
        dh1.withUnsafeBytes { combinedSecret.append(contentsOf: $0) }
        dh2.withUnsafeBytes { combinedSecret.append(contentsOf: $0) }
        dh3.withUnsafeBytes { combinedSecret.append(contentsOf: $0) }
        dh4.withUnsafeBytes { combinedSecret.append(contentsOf: $0) }

        Log.info("[X3DH] Initiator: Combined secret length: \(combinedSecret.count) bytes")

        return combinedSecret
    }

    public func performResponderKeyAgreement(
        alicesBundle: X3DHPublicKeyBundle,
        bobIdentityPrivate: Data,
        bobSignedPreKeyPrivate: Data,
        bobEphemeralPrivate: Data
    ) throws -> Data {

        try validatePublicKeyBundle(alicesBundle)

        let IK_B = try keyExchange.privateKeyFromBytes(bobIdentityPrivate)
        let SPK_B = try keyExchange.privateKeyFromBytes(bobSignedPreKeyPrivate)
        let EPK_B = try keyExchange.privateKeyFromBytes(bobEphemeralPrivate)

        let IK_A = try keyExchange.publicKeyFromBytes(alicesBundle.identityPublicKey)
        let EK_A = try keyExchange.publicKeyFromBytes(alicesBundle.ephemeralPublicKey)

        let dh1 = try keyExchange.performKeyAgreement(privateKey: SPK_B, publicKey: IK_A)

        let dh2 = try keyExchange.performKeyAgreement(privateKey: IK_B, publicKey: EK_A)

        let dh3 = try keyExchange.performKeyAgreement(privateKey: SPK_B, publicKey: EK_A)

        let dh4 = try keyExchange.performKeyAgreement(privateKey: EPK_B, publicKey: EK_A)

        var combinedSecret = Data()
        dh1.withUnsafeBytes { combinedSecret.append(contentsOf: $0) }
        dh2.withUnsafeBytes { combinedSecret.append(contentsOf: $0) }
        dh3.withUnsafeBytes { combinedSecret.append(contentsOf: $0) }
        dh4.withUnsafeBytes { combinedSecret.append(contentsOf: $0) }

        Log.info("[X3DH] Responder: Combined secret length: \(combinedSecret.count) bytes")

        return combinedSecret
    }

    public func deriveInitialKeys(from sharedSecret: Data) throws -> (rootKey: Data, sendingChainKey: Data, receivingChainKey: Data) {

        let (rootKey, initialChain) = try HKDFKeyDerivation.deriveRootAndChainKeys(
            from: sharedSecret,
            info: CryptographicConstants.x3dhInfo
        )

        let sendingChainKey = try HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: initialChain,
            salt: nil,
            info: Data("ecliptix-sender-chain".utf8),
            outputByteCount: 32
        )

        let receivingChainKey = try HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: initialChain,
            salt: nil,
            info: Data("ecliptix-receiver-chain".utf8),
            outputByteCount: 32
        )

        Log.info("[X3DH] Derived root key and initial chain keys")

        return (rootKey, sendingChainKey, receivingChainKey)
    }

    private func signPreKey(
        preKeyPublic: Curve25519.KeyAgreement.PublicKey,
        identityPrivate: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {

        let preKeyBytes = keyExchange.publicKeyToBytes(preKeyPublic)

        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyExchange.privateKeyToBytes(identityPrivate))

        let signature = try signingKey.signature(for: preKeyBytes)

        Log.debug("[X3DH] Signed pre-key with Ed25519")
        return signature
    }

    private func verifyPreKeySignature(
        preKeyPublic: Data,
        signature: Data,
        identityPublic: Data
    ) throws -> Bool {

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: identityPublic)

        let isValid = publicKey.isValidSignature(signature, for: preKeyPublic)

        Log.debug("[X3DH] Pre-key signature verification: \(isValid ? "VALID" : "INVALID")")
        return isValid
    }

    private func validatePublicKeyBundle(_ bundle: X3DHPublicKeyBundle) throws {
        guard bundle.identityPublicKey.count == 32 else {
            throw X3DHError.invalidBundle("Invalid identity public key size")
        }

        guard bundle.signedPreKeyPublicKey.count == 32 else {
            throw X3DHError.invalidBundle("Invalid signed pre-key size")
        }

        guard bundle.ephemeralPublicKey.count == 32 else {
            throw X3DHError.invalidBundle("Invalid ephemeral key size")
        }

        guard bundle.signedPreKeySignature.count > 0 else {
            throw X3DHError.invalidBundle("Missing signature")
        }

        let isValid = try verifyPreKeySignature(
            preKeyPublic: bundle.signedPreKeyPublicKey,
            signature: bundle.signedPreKeySignature,
            identityPublic: bundle.identityPublicKey
        )

        guard isValid else {
            throw X3DHError.invalidSignature
        }

        Log.info("[X3DH] Bundle validation successful")
    }
}

public struct PreKeyBundle {
    public let identityPublicKey: Data
    public let identityPrivateKey: Data
    public let signedPreKeyId: UInt32
    public let signedPreKeyPublicKey: Data
    public let signedPreKeyPrivateKey: Data
    public let signedPreKeySignature: Data
    public let ephemeralPublicKey: Data
    public let ephemeralPrivateKey: Data

    public init(
        identityPublicKey: Data,
        identityPrivateKey: Data,
        signedPreKeyId: UInt32,
        signedPreKeyPublicKey: Data,
        signedPreKeyPrivateKey: Data,
        signedPreKeySignature: Data,
        ephemeralPublicKey: Data,
        ephemeralPrivateKey: Data
    ) {
        self.identityPublicKey = identityPublicKey
        self.identityPrivateKey = identityPrivateKey
        self.signedPreKeyId = signedPreKeyId
        self.signedPreKeyPublicKey = signedPreKeyPublicKey
        self.signedPreKeyPrivateKey = signedPreKeyPrivateKey
        self.signedPreKeySignature = signedPreKeySignature
        self.ephemeralPublicKey = ephemeralPublicKey
        self.ephemeralPrivateKey = ephemeralPrivateKey
    }
}

public struct PersistentKeyBundle: Codable {
    public let identityPublicKey: Data
    public let identityPrivateKey: Data
    public let signedPreKeyId: UInt32
    public let signedPreKeyPublicKey: Data
    public let signedPreKeyPrivateKey: Data
    public let signedPreKeySignature: Data

    public init(
        identityPublicKey: Data,
        identityPrivateKey: Data,
        signedPreKeyId: UInt32,
        signedPreKeyPublicKey: Data,
        signedPreKeyPrivateKey: Data,
        signedPreKeySignature: Data
    ) {
        self.identityPublicKey = identityPublicKey
        self.identityPrivateKey = identityPrivateKey
        self.signedPreKeyId = signedPreKeyId
        self.signedPreKeyPublicKey = signedPreKeyPublicKey
        self.signedPreKeyPrivateKey = signedPreKeyPrivateKey
        self.signedPreKeySignature = signedPreKeySignature
    }
}

public struct X3DHPublicKeyBundle: Codable {
    public let identityPublicKey: Data
    public let signedPreKeyId: UInt32
    public let signedPreKeyPublicKey: Data
    public let signedPreKeySignature: Data
    public let ephemeralPublicKey: Data

    public init(
        identityPublicKey: Data,
        signedPreKeyId: UInt32,
        signedPreKeyPublicKey: Data,
        signedPreKeySignature: Data,
        ephemeralPublicKey: Data
    ) {
        self.identityPublicKey = identityPublicKey
        self.signedPreKeyId = signedPreKeyId
        self.signedPreKeyPublicKey = signedPreKeyPublicKey
        self.signedPreKeySignature = signedPreKeySignature
        self.ephemeralPublicKey = ephemeralPublicKey
    }
}

public enum X3DHError: LocalizedError {
    case invalidBundle(String)
    case invalidSignature
    case keyAgreementFailed(String)
    case derivationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBundle(let msg):
            return "Invalid key bundle: \(msg)"
        case .invalidSignature:
            return "Pre-key signature verification failed"
        case .keyAgreementFailed(let msg):
            return "Key agreement failed: \(msg)"
        case .derivationFailed(let msg):
            return "Key derivation failed: \(msg)"
        }
    }
}
