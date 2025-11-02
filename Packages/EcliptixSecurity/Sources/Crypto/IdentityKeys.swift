import Crypto
import CryptoKit
import EcliptixCore
import Foundation

public final class OneTimePreKey {
    public let preKeyId: UInt32
    private var privateKey: Data
    public let publicKey: Data

    public init(preKeyId: UInt32, privateKey: Data, publicKey: Data) {
        self.preKeyId = preKeyId
        self.privateKey = privateKey
        self.publicKey = publicKey
    }

    deinit {

        CryptographicHelpers.secureWipe(&privateKey)
    }

    public static func generate(preKeyId: UInt32) throws -> OneTimePreKey {
        let x25519 = X25519KeyExchange()
        let (privateKey, publicKey) = x25519.generateKeyPair()
        let privateKeyBytes = x25519.privateKeyToBytes(privateKey)
        let publicKeyBytes = x25519.publicKeyToBytes(publicKey)

        return OneTimePreKey(
            preKeyId: preKeyId,
            privateKey: privateKeyBytes,
            publicKey: publicKeyBytes
        )
    }

    public func getPrivateKey() -> Data? {
        return Data(privateKey)
    }

    public func getPublicKey() -> Data {
        return Data(publicKey)
    }
}

public final class IdentityKeys: @unchecked Sendable {

    private let lock = NSLock()

    private var ed25519SecretKey: Data
    public let ed25519PublicKey: Data

    private var identityX25519SecretKey: Data
    public let identityX25519PublicKey: Data

    public let signedPreKeyId: UInt32
    private var signedPreKeySecret: Data
    public let signedPreKeyPublic: Data
    public let signedPreKeySignature: Data

    private var oneTimePreKeys: [OneTimePreKey]

    private var ephemeralSecretKey: Data?
    private var ephemeralPublicKey: Data?

    private init(
        ed25519SecretKey: Data,
        ed25519PublicKey: Data,
        identityX25519SecretKey: Data,
        identityX25519PublicKey: Data,
        signedPreKeyId: UInt32,
        signedPreKeySecret: Data,
        signedPreKeyPublic: Data,
        signedPreKeySignature: Data,
        oneTimePreKeys: [OneTimePreKey]
    ) {
        self.ed25519SecretKey = ed25519SecretKey
        self.ed25519PublicKey = ed25519PublicKey
        self.identityX25519SecretKey = identityX25519SecretKey
        self.identityX25519PublicKey = identityX25519PublicKey
        self.signedPreKeyId = signedPreKeyId
        self.signedPreKeySecret = signedPreKeySecret
        self.signedPreKeyPublic = signedPreKeyPublic
        self.signedPreKeySignature = signedPreKeySignature
        self.oneTimePreKeys = oneTimePreKeys
    }

    deinit {

        CryptographicHelpers.secureWipe(&ed25519SecretKey)
        CryptographicHelpers.secureWipe(&identityX25519SecretKey)
        CryptographicHelpers.secureWipe(&signedPreKeySecret)

        if ephemeralSecretKey != nil {
            CryptographicHelpers.secureWipe(&ephemeralSecretKey!)
        }
        if ephemeralPublicKey != nil {
            CryptographicHelpers.secureWipe(&ephemeralPublicKey!)
        }

    }

    public static func create(oneTimeKeyCount: UInt32 = 100) throws -> IdentityKeys {
        guard oneTimeKeyCount <= Int32.max else {
            throw ProtocolFailure.generic("One-time key count exceeds limits")
        }

        let ed25519PrivateKey = Curve25519.Signing.PrivateKey()
        let ed25519SecretKeyBytes = ed25519PrivateKey.rawRepresentation
        let ed25519PublicKeyBytes = ed25519PrivateKey.publicKey.rawRepresentation

        let x25519 = X25519KeyExchange()
        let (identityPrivateKey, identityPublicKey) = x25519.generateKeyPair()
        let identityPrivateKeyBytes = x25519.privateKeyToBytes(identityPrivateKey)
        let identityPublicKeyBytes = x25519.publicKeyToBytes(identityPublicKey)

        let signedPreKeyId = UInt32.random(in: 1...UInt32.max)
        let (spkPrivateKey, spkPublicKey) = x25519.generateKeyPair()
        let spkPrivateKeyBytes = x25519.privateKeyToBytes(spkPrivateKey)
        let spkPublicKeyBytes = x25519.publicKeyToBytes(spkPublicKey)

        guard let signatureBytes = try? ed25519PrivateKey.signature(for: spkPublicKeyBytes) else {
            throw ProtocolFailure.generic("Failed to sign pre-key")
        }

        var oneTimePreKeys: [OneTimePreKey] = []
        var usedIds = Set<UInt32>()
        var idCounter: UInt32 = 2

        for _ in 0..<oneTimeKeyCount {
            var id = idCounter
            idCounter += 1

            while usedIds.contains(id) {
                id = UInt32.random(in: 1...UInt32.max)
            }
            usedIds.insert(id)

            let opk = try OneTimePreKey.generate(preKeyId: id)
            oneTimePreKeys.append(opk)
        }

        let keys = IdentityKeys(
            ed25519SecretKey: Data(ed25519SecretKeyBytes),
            ed25519PublicKey: Data(ed25519PublicKeyBytes),
            identityX25519SecretKey: identityPrivateKeyBytes,
            identityX25519PublicKey: identityPublicKeyBytes,
            signedPreKeyId: signedPreKeyId,
            signedPreKeySecret: spkPrivateKeyBytes,
            signedPreKeyPublic: spkPublicKeyBytes,
            signedPreKeySignature: Data(signatureBytes),
            oneTimePreKeys: oneTimePreKeys
        )

        return keys
    }

    public static func createFromMasterKey(
        masterKey: Data,
        membershipId: String,
        oneTimeKeyCount: UInt32 = 100
    ) throws -> IdentityKeys {

        let ed25519Info = Data("ecliptix-ed25519-\(membershipId)".utf8)
        let ed25519Seed = try HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: masterKey,
            salt: nil,
            info: ed25519Info,
            outputByteCount: 32
        )

        let ed25519PrivateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: ed25519Seed)
        let ed25519SecretKeyBytes = ed25519PrivateKey.rawRepresentation
        let ed25519PublicKeyBytes = ed25519PrivateKey.publicKey.rawRepresentation

        let x25519Info = Data("ecliptix-x25519-\(membershipId)".utf8)
        let x25519Seed = try HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: masterKey,
            salt: nil,
            info: x25519Info,
            outputByteCount: 32
        )

        let x25519 = X25519KeyExchange()
        let identityPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: x25519Seed)
        let identityPrivateKeyBytes = x25519.privateKeyToBytes(identityPrivateKey)
        let identityPublicKeyBytes = x25519.publicKeyToBytes(identityPrivateKey.publicKey)

        let spkInfo = Data("ecliptix-spk-\(membershipId)".utf8)
        let spkSeed = try HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: masterKey,
            salt: nil,
            info: spkInfo,
            outputByteCount: 36
        )

        let signedPreKeyId = spkSeed.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let spkKeyMaterial = spkSeed.suffix(32)

        let spkPrivateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: spkKeyMaterial)
        let spkPrivateKeyBytes = x25519.privateKeyToBytes(spkPrivateKey)
        let spkPublicKeyBytes = x25519.publicKeyToBytes(spkPrivateKey.publicKey)

        let signatureBytes = try ed25519PrivateKey.signature(for: spkPublicKeyBytes)

        var oneTimePreKeys: [OneTimePreKey] = []
        for i in 0..<oneTimeKeyCount {
            let opk = try OneTimePreKey.generate(preKeyId: UInt32(i + 2))
            oneTimePreKeys.append(opk)
        }

        let keys = IdentityKeys(
            ed25519SecretKey: Data(ed25519SecretKeyBytes),
            ed25519PublicKey: Data(ed25519PublicKeyBytes),
            identityX25519SecretKey: identityPrivateKeyBytes,
            identityX25519PublicKey: identityPublicKeyBytes,
            signedPreKeyId: signedPreKeyId,
            signedPreKeySecret: spkPrivateKeyBytes,
            signedPreKeyPublic: spkPublicKeyBytes,
            signedPreKeySignature: Data(signatureBytes),
            oneTimePreKeys: oneTimePreKeys
        )

        return keys
    }

    public func createPublicBundle() -> PublicKeyBundle {
        lock.lock()
        defer { lock.unlock() }

        let opkRecords = oneTimePreKeys.map { opk -> PublicKeyBundle.OneTimePreKey in
            var record = PublicKeyBundle.OneTimePreKey()
            record.preKeyID = opk.preKeyId
            record.publicKey = opk.getPublicKey()
            return record
        }

        var bundle = PublicKeyBundle()
        bundle.identityPublicKey = Data(ed25519PublicKey)
        bundle.identityX25519PublicKey = Data(identityX25519PublicKey)
        bundle.signedPreKeyID = signedPreKeyId
        bundle.signedPreKeyPublicKey = Data(signedPreKeyPublic)
        bundle.signedPreKeySignature = Data(signedPreKeySignature)
        bundle.oneTimePreKeys = opkRecords
        if let ephemeral = ephemeralPublicKey {
            bundle.ephemeralX25519PublicKey = Data(ephemeral)
        }

        return bundle
    }

    public func generateEphemeralKeyPair() {
        lock.lock()
        defer { lock.unlock() }

        if ephemeralSecretKey != nil {
            CryptographicHelpers.secureWipe(&ephemeralSecretKey!)
        }
        if ephemeralPublicKey != nil {
            CryptographicHelpers.secureWipe(&ephemeralPublicKey!)
        }

        let x25519 = X25519KeyExchange()
        let (privateKey, publicKey) = x25519.generateKeyPair()
        ephemeralSecretKey = x25519.privateKeyToBytes(privateKey)
        ephemeralPublicKey = x25519.publicKeyToBytes(publicKey)
    }

    public func x3dhDeriveSharedSecret(
        remoteBundle: PublicKeyBundle,
        info: Data
    ) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard let ephemeralSecretKey = ephemeralSecretKey else {
            throw ProtocolFailure.generic("Ephemeral key not generated")
        }

        guard remoteBundle.identityX25519PublicKey.count == CryptographicConstants.x25519KeySize else {
            throw ProtocolFailure.generic("Invalid remote identity key size")
        }
        guard remoteBundle.signedPreKeyPublicKey.count == CryptographicConstants.x25519KeySize else {
            throw ProtocolFailure.generic("Invalid remote signed pre-key size")
        }

        let x25519 = X25519KeyExchange()

        let dh1 = try x25519.performKeyAgreementWithBytes(
            privateKeyBytes: identityX25519SecretKey,
            publicKeyBytes: remoteBundle.signedPreKeyPublicKey
        )

        let dh2 = try x25519.performKeyAgreementWithBytes(
            privateKeyBytes: ephemeralSecretKey,
            publicKeyBytes: remoteBundle.identityX25519PublicKey
        )

        let dh3 = try x25519.performKeyAgreementWithBytes(
            privateKeyBytes: ephemeralSecretKey,
            publicKeyBytes: remoteBundle.signedPreKeyPublicKey
        )

        var dhCombined = Data()
        dhCombined.append(dh1)
        dhCombined.append(dh2)
        dhCombined.append(dh3)

        if let firstOpk = remoteBundle.oneTimePreKeys.first,
           firstOpk.publicKey.count == CryptographicConstants.x25519KeySize {
            let dh4 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: ephemeralSecretKey,
                publicKeyBytes: firstOpk.publicKey
            )
            dhCombined.append(dh4)
        }

        var ikm = Data([0xFF])
        ikm.append(dhCombined)

        let sharedSecret = try HKDFKeyDerivation.deriveKey(
            inputKeyMaterial: ikm,
            salt: nil,
            info: info,
            outputByteCount: CryptographicConstants.x25519KeySize
        )

        return sharedSecret
    }

    public func calculateSharedSecretAsRecipient(
        remoteIdentityPublicKey: Data,
        remoteEphemeralPublicKey: Data,
        usedLocalOpkId: UInt32?,
        info: Data
    ) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard remoteIdentityPublicKey.count == CryptographicConstants.x25519KeySize else {
            throw ProtocolFailure.generic("Invalid remote identity key size")
        }
        guard remoteEphemeralPublicKey.count == CryptographicConstants.x25519KeySize else {
            throw ProtocolFailure.generic("Invalid remote ephemeral key size")
        }

        let x25519 = X25519KeyExchange()

        do {
            let dh1 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: signedPreKeySecret,
                publicKeyBytes: remoteEphemeralPublicKey
            )

            let dh2 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: identityX25519SecretKey,
                publicKeyBytes: remoteEphemeralPublicKey
            )

            let dh3 = try x25519.performKeyAgreementWithBytes(
                privateKeyBytes: signedPreKeySecret,
                publicKeyBytes: remoteIdentityPublicKey
            )

            var dhCombined = Data()
            dhCombined.append(dh3)
            dhCombined.append(dh2)
            dhCombined.append(dh1)

            if let opkId = usedLocalOpkId {
                guard let opk = oneTimePreKeys.first(where: { $0.preKeyId == opkId }) else {
                    throw ProtocolFailure.generic("Used one-time pre-key not found: \(opkId)")
                }

                guard let opkPrivateKey = opk.getPrivateKey() else {
                    throw ProtocolFailure.generic("One-time pre-key private key not available")
                }

                let dh4 = try x25519.performKeyAgreementWithBytes(
                    privateKeyBytes: opkPrivateKey,
                    publicKeyBytes: remoteEphemeralPublicKey
                )
                dhCombined.append(dh4)
            }

            var ikm = Data([0xFF])
            ikm.append(dhCombined)

            let sharedSecret = try HKDFKeyDerivation.deriveKey(
                inputKeyMaterial: ikm,
                salt: nil,
                info: info,
                outputByteCount: CryptographicConstants.x25519KeySize
            )

            return sharedSecret
        } catch {
            throw ProtocolFailure.generic("Recipient key agreement failed: \(error.localizedDescription)")
        }
    }

    public static func verifyRemoteSpkSignature(
        remoteIdentityEd25519: Data,
        remoteSpkPublic: Data,
        remoteSpkSignature: Data
    ) throws -> Bool {

        guard remoteIdentityEd25519.count == 32 else {
            throw ProtocolFailure.generic("Invalid Ed25519 public key size")
        }
        guard remoteSpkPublic.count == CryptographicConstants.x25519KeySize else {
            throw ProtocolFailure.generic("Invalid signed pre-key size")
        }
        guard remoteSpkSignature.count == 64 else {
            throw ProtocolFailure.generic("Invalid signature size")
        }

        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: remoteIdentityEd25519)
            let isValid = publicKey.isValidSignature(remoteSpkSignature, for: remoteSpkPublic)
            return isValid
        } catch {
            throw ProtocolFailure.generic("Signature verification failed: \(error.localizedDescription)")
        }
    }

    public func toProtoState() throws -> IdentityKeysState {
        lock.lock()
        defer { lock.unlock() }

        let opkSecrets = oneTimePreKeys.compactMap { opk -> OneTimePreKeySecret? in
            guard let privateKey = opk.getPrivateKey() else { return nil }
            return OneTimePreKeySecret(
                preKeyId: opk.preKeyId,
                privateKey: privateKey,
                publicKey: opk.getPublicKey()
            )
        }

        let state = IdentityKeysState(
            ed25519SecretKey: Data(ed25519SecretKey),
            identityX25519SecretKey: Data(identityX25519SecretKey),
            signedPreKeySecret: Data(signedPreKeySecret),
            oneTimePreKeys: opkSecrets,
            ed25519PublicKey: Data(ed25519PublicKey),
            identityX25519PublicKey: Data(identityX25519PublicKey),
            signedPreKeyId: signedPreKeyId,
            signedPreKeyPublic: Data(signedPreKeyPublic),
            signedPreKeySignature: Data(signedPreKeySignature)
        )

        return state
    }

    public static func fromProtoState(_ state: IdentityKeysState) throws -> IdentityKeys {

        var oneTimePreKeys: [OneTimePreKey] = []
        for opkSecret in state.oneTimePreKeys {
            let opk = OneTimePreKey(
                preKeyId: opkSecret.preKeyId,
                privateKey: Data(opkSecret.privateKey),
                publicKey: Data(opkSecret.publicKey)
            )
            oneTimePreKeys.append(opk)
        }

        let keys = IdentityKeys(
            ed25519SecretKey: Data(state.ed25519SecretKey),
            ed25519PublicKey: Data(state.ed25519PublicKey),
            identityX25519SecretKey: Data(state.identityX25519SecretKey),
            identityX25519PublicKey: Data(state.identityX25519PublicKey),
            signedPreKeyId: state.signedPreKeyId,
            signedPreKeySecret: Data(state.signedPreKeySecret),
            signedPreKeyPublic: Data(state.signedPreKeyPublic),
            signedPreKeySignature: Data(state.signedPreKeySignature),
            oneTimePreKeys: oneTimePreKeys
        )

        return keys
    }

    public func getIdentityX25519PublicKey() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return Data(identityX25519PublicKey)
    }
}
extension IdentityKeys: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "IdentityKeys(signedPreKeyId: \(signedPreKeyId), oneTimePreKeys: \(oneTimePreKeys.count))"
    }
}
